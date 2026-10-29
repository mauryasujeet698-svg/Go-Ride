import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key, required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Go-Ride Operations'),
            actions: [
              IconButton(
                tooltip: 'Sign out',
                onPressed: onSignOut,
                icon: const Icon(Icons.logout),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
                Tab(icon: Icon(Icons.tune), text: 'Business'),
                Tab(icon: Icon(Icons.price_change_outlined), text: 'Fares'),
                Tab(icon: Icon(Icons.card_membership), text: 'Plans'),
                Tab(icon: Icon(Icons.auto_awesome), text: 'AI & Reports'),
                Tab(icon: Icon(Icons.support_agent), text: 'Operations'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _OverviewTab(),
              _BusinessTab(),
              _FarePricingTab(),
              _PlansTab(),
              _AiReportsTab(),
              _OperationsTab(),
            ],
          ),
        ),
      );
}

SupabaseClient get _db => Supabase.instance.client;

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _value(Map<String, dynamic> row, String key, [String fallback = '—']) {
  final value = row[key];
  return value == null || value.toString().isEmpty ? fallback : value.toString();
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rides = [];
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _applications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rides = await _db.from('rides').select('id,status,category,fare_minor,currency,created_at').order('created_at', ascending: false).limit(10);
      final tickets = await _db.from('support_tickets').select('id,subject,status,needs_human,priority,created_at').order('created_at', ascending: false).limit(50);
      final applications = await _db.from('driver_applications').select('id,status').eq('status', 'pending').limit(100);
      if (!mounted) return;
      setState(() {
        _rides = List<Map<String, dynamic>>.from(rides);
        _tickets = List<Map<String, dynamic>>.from(tickets);
        _applications = List<Map<String, dynamic>>.from(applications);
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load operational data. Verify the admin role and database policies.');
      debugPrint('Admin overview load failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Operational overview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Pull down to refresh. Counts below reflect the latest rows returned by the backend, not estimates from AI.'),
            const SizedBox(height: 16),
            if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!))),
            if (_loading) const LinearProgressIndicator(),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricCard(label: 'Recent rides', value: _rides.length.toString(), icon: Icons.local_taxi),
                _MetricCard(label: 'Human escalations', value: _tickets.where((r) => r['needs_human'] == true).length.toString(), icon: Icons.support_agent),
                _MetricCard(label: 'Pending applications', value: _applications.length.toString(), icon: Icons.person_search),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Latest rides', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (_rides.isEmpty && !_loading) const ListTile(title: Text('No rides recorded yet.')),
            for (final ride in _rides)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.local_taxi),
                  title: Text(_value(ride, 'category') + ' · ' + _value(ride, 'status')),
                  subtitle: Text(_value(ride, 'created_at')),
                  trailing: Text(_value(ride, 'currency', 'INR') + ' ' + (((ride['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
                ),
              ),
            const SizedBox(height: 16),
            const Text('Support requiring attention', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final ticket in _tickets.where((r) => r['needs_human'] == true || r['priority'] == 'urgent').take(10))
              Card(
                child: ListTile(
                  leading: Icon(ticket['priority'] == 'urgent' ? Icons.warning_amber : Icons.support_agent),
                  title: Text(_value(ticket, 'subject')),
                  subtitle: Text(_value(ticket, 'status') + ' · ' + _value(ticket, 'priority', 'normal')),
                ),
              ),
          ],
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 155,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(height: 10),
                Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text(label),
              ],
            ),
          ),
        ),
      );
}

class _BusinessTab extends StatefulWidget {
  const _BusinessTab();

  @override
  State<_BusinessTab> createState() => _BusinessTabState();
}

class _BusinessTabState extends State<_BusinessTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _areas = [];
  Map<String, Map<String, dynamic>> _settings = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final areas = await _db.from('service_areas').select().order('code');
      final settings = await _db.from('area_business_settings').select();
      if (!mounted) return;
      setState(() {
        _areas = List<Map<String, dynamic>>.from(areas);
        _settings = {
          for (final row in List<Map<String, dynamic>>.from(settings))
            row['area_id'].toString() + ':' + row['service'].toString(): row,
        };
      });
    } catch (error) {
      if (mounted) _toast(context, 'Could not load service areas. Check admin RLS policies.');
      debugPrint('Business settings load failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editArea([Map<String, dynamic>? area]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AreaEditor(area: area),
    );
    if (result == null) return;
    try {
      final id = area?['id']?.toString();
      if (id == null) {
        final inserted = await _db.from('service_areas').insert(result).select('id').single();
        await _db.from('area_business_settings').upsert({
          'area_id': inserted['id'],
          'service': 'ride',
          'business_model': 'subscription',
          'commission_bps': 0,
          'active': true,
          'updated_by': _db.auth.currentUser?.id,
        }, onConflict: 'area_id,service');
      } else {
        await _db.from('service_areas').update({...result, 'updated_by': _db.auth.currentUser?.id}).eq('id', id);
      }
      if (mounted) _toast(context, 'Service area saved.');
      await _load();
    } catch (error) {
      if (mounted) _toast(context, 'Could not save area. Check the code, PIN code and coverage centre.');
      debugPrint('Service area save failed: $error');
    }
  }

  Future<void> _editModel(Map<String, dynamic> area) async {
    final areaId = area['id'].toString();
    final existing = _settings[areaId + ':ride'];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BusinessModelEditor(
        model: _value(existing ?? {}, 'business_model', 'subscription'),
        commissionPercent: ((existing?['commission_bps'] as num?)?.toDouble() ?? 0) / 100,
        active: existing?['active'] as bool? ?? true,
      ),
    );
    if (result == null) return;
    try {
      await _db.from('area_business_settings').upsert({
        'area_id': areaId,
        'service': 'ride',
        'business_model': result['business_model'],
        'commission_bps': result['commission_bps'],
        'active': result['active'],
        'updated_by': _db.auth.currentUser?.id,
      }, onConflict: 'area_id,service');
      if (mounted) _toast(context, 'Business model updated for ' + _value(area, 'name') + '.');
      await _load();
    } catch (error) {
      if (mounted) _toast(context, 'Could not update business model. Confirm your account has the admin role.');
      debugPrint('Business model update failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(child: Text('Cities and service areas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                FilledButton.icon(onPressed: _loading ? null : () => _editArea(), icon: const Icon(Icons.add), label: const Text('Add area')),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Area coverage uses a centre point and radius. PIN code is stored for display and administration; precise postal-boundary matching needs a trusted polygon/geocoding source.'),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            for (final area in _areas)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(area['active'] == true ? Icons.location_on : Icons.location_off),
                        title: Text(_value(area, 'name') + ' · ' + _value(area, 'code')),
                        subtitle: Text([
                          _value(area, 'city', ''),
                          _value(area, 'state', ''),
                          _value(area, 'pincode', 'No PIN code'),
                          'Radius ' + _value(area, 'coverage_radius_km', '0') + ' km',
                          area['active'] == true ? 'Enabled' : 'Disabled',
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        trailing: IconButton(tooltip: 'Edit area', onPressed: () => _editArea(area), icon: const Icon(Icons.edit_outlined)),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _editModel(area),
                          icon: const Icon(Icons.tune),
                          label: Text('Ride model: ' + _value(_settings[area['id'].toString() + ':ride'] ?? {}, 'business_model', 'not configured')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_loading && _areas.isEmpty) const ListTile(title: Text('No service areas configured.')),
          ],
        ),
      );
}

class _AreaEditor extends StatefulWidget {
  const _AreaEditor({this.area});
  final Map<String, dynamic>? area;

  @override
  State<_AreaEditor> createState() => _AreaEditorState();
}

class _AreaEditorState extends State<_AreaEditor> {
  late final TextEditingController _code = TextEditingController(text: _value(widget.area ?? {}, 'code', ''));
  late final TextEditingController _name = TextEditingController(text: _value(widget.area ?? {}, 'name', ''));
  late final TextEditingController _city = TextEditingController(text: _value(widget.area ?? {}, 'city', ''));
  late final TextEditingController _district = TextEditingController(text: _value(widget.area ?? {}, 'district', ''));
  late final TextEditingController _state = TextEditingController(text: _value(widget.area ?? {}, 'state', ''));
  late final TextEditingController _pincode = TextEditingController(text: _value(widget.area ?? {}, 'pincode', ''));
  late final TextEditingController _lat = TextEditingController(text: _value(widget.area ?? {}, 'center_lat', ''));
  late final TextEditingController _lng = TextEditingController(text: _value(widget.area ?? {}, 'center_lng', ''));
  late final TextEditingController _radius = TextEditingController(text: _value(widget.area ?? {}, 'coverage_radius_km', '0'));
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _active = widget.area?['active'] as bool? ?? false;
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _city, _district, _state, _pincode, _lat, _lng, _radius]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _optionalDouble(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : double.tryParse(controller.text.trim());

  void _save() {
    final code = _code.text.trim().toUpperCase();
    final name = _name.text.trim();
    final pincode = _pincode.text.trim();
    final lat = _optionalDouble(_lat);
    final lng = _optionalDouble(_lng);
    final radius = double.tryParse(_radius.text.trim()) ?? 0;
    if (code.length < 2 || name.length < 2) {
      _toast(context, 'Enter a valid area code and name.');
      return;
    }
    if (pincode.isNotEmpty && !RegExp(r'^[1-9][0-9]{5}$').hasMatch(pincode)) {
      _toast(context, 'Enter a valid six-digit Indian PIN code.');
      return;
    }
    if (_active && code != 'DEFAULT' && (lat == null || lng == null || radius <= 0)) {
      _toast(context, 'Active area-specific coverage requires centre latitude, longitude and a positive radius.');
      return;
    }
    if ((lat == null) != (lng == null) || (lat != null && (lat < -90 || lat > 90)) || (lng != null && (lng < -180 || lng > 180)) || radius < 0 || radius > 200) {
      _toast(context, 'Check coordinates and radius.');
      return;
    }
    Navigator.of(context).pop({
      'code': code,
      'name': name,
      'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
      'district': _district.text.trim().isEmpty ? null : _district.text.trim(),
      'state': _state.text.trim().isEmpty ? null : _state.text.trim(),
      'pincode': pincode.isEmpty ? null : pincode,
      'center_lat': lat,
      'center_lng': lng,
      'coverage_radius_km': radius,
      'active': _active,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.area == null ? 'Add service area' : 'Edit service area'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Unique area code')),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Area name')),
                TextField(controller: _city, decoration: const InputDecoration(labelText: 'City')),
                TextField(controller: _district, decoration: const InputDecoration(labelText: 'District')),
                TextField(controller: _state, decoration: const InputDecoration(labelText: 'State')),
                TextField(controller: _pincode, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN code (optional)')),
                const Divider(height: 24),
                const Align(alignment: Alignment.centerLeft, child: Text('Coverage centre and radius', style: TextStyle(fontWeight: FontWeight.bold))),
                TextField(controller: _lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Centre latitude')),
                TextField(controller: _lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Centre longitude')),
                TextField(controller: _radius, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Radius in km (0–200)')),
                SwitchListTile(value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Area enabled')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save area')),
        ],
      );
}

class _BusinessModelEditor extends StatefulWidget {
  const _BusinessModelEditor({required this.model, required this.commissionPercent, required this.active});
  final String model;
  final double commissionPercent;
  final bool active;

  @override
  State<_BusinessModelEditor> createState() => _BusinessModelEditorState();
}

class _BusinessModelEditorState extends State<_BusinessModelEditor> {
  late String _model = widget.model;
  late final TextEditingController _commission = TextEditingController(text: widget.commissionPercent.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), ''));
  late bool _active = widget.active;

  @override
  void dispose() {
    _commission.dispose();
    super.dispose();
  }

  void _save() {
    final percent = double.tryParse(_commission.text.trim()) ?? 0;
    if (percent < 0 || percent > 100) {
      _toast(context, 'Commission must be between 0% and 100%.');
      return;
    }
    Navigator.of(context).pop({
      'business_model': _model,
      'commission_bps': (percent * 100).round(),
      'active': _active,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ride business model'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _model,
              decoration: const InputDecoration(labelText: 'Business model'),
              items: const [
                DropdownMenuItem(value: 'subscription', child: Text('Subscription')),
                DropdownMenuItem(value: 'commission', child: Text('Commission')),
                DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
              ],
              onChanged: (v) => setState(() => _model = v ?? 'subscription'),
            ),
            TextField(
              controller: _commission,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Commission (%)', helperText: 'Used only for commission-based areas.'),
            ),
            SwitchListTile(value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Service setting active')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save model')),
        ],
      );
}

class _FarePricingTab extends StatefulWidget {
  const _FarePricingTab();

  @override
  State<_FarePricingTab> createState() => _FarePricingTabState();
}

class _FarePricingTabState extends State<_FarePricingTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _rules = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _db.from('pricing_rules')
          .select('category,base_fare_minor,per_km_minor,minimum_fare_minor,currency,enabled')
          .order('category');
      if (mounted) setState(() => _rules = List<Map<String, dynamic>>.from(rows));
    } catch (error) {
      if (mounted) _toast(context, 'Could not load fare rules. Verify admin access.');
      debugPrint('Fare rule load failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> rule) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FareRuleEditor(rule: rule),
    );
    if (result == null) return;
    try {
      await _db.from('pricing_rules').update(result).eq('category', rule['category']);
      if (mounted) _toast(context, 'Fare rule updated for ' + _value(rule, 'category') + '.');
      await _load();
    } catch (error) {
      if (mounted) _toast(context, 'Could not update fare rule.');
      debugPrint('Fare rule update failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Fare pricing', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Rates are stored in Supabase and take effect without publishing a new APK. Review prices and local regulations before enabling a category in production. Changes are recorded in the audit log.'),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            for (final rule in _rules)
              Card(
                child: ListTile(
                  leading: Icon(
                    rule['category'] == 'BIKE' ? Icons.two_wheeler
                      : rule['category'] == 'AUTO' ? Icons.electric_rickshaw
                      : rule['category'] == 'SEDAN' ? Icons.local_taxi
                      : Icons.directions_car,
                  ),
                  title: Text(_value(rule, 'category') + (rule['enabled'] == true ? ' · Enabled' : ' · Disabled')),
                  subtitle: Text(
                    'Base: INR ' + (((rule['base_fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2) +
                    ' · Per km: INR ' + (((rule['per_km_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2) +
                    ' · Minimum: INR ' + (((rule['minimum_fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2),
                  ),
                  trailing: IconButton(onPressed: () => _edit(rule), icon: const Icon(Icons.edit_outlined)),
                ),
              ),
            if (!_loading && _rules.isEmpty) const ListTile(title: Text('No fare rules found.')),
          ],
        ),
      );
}

class _FareRuleEditor extends StatefulWidget {
  const _FareRuleEditor({required this.rule});
  final Map<String, dynamic> rule;

  @override
  State<_FareRuleEditor> createState() => _FareRuleEditorState();
}

class _FareRuleEditorState extends State<_FareRuleEditor> {
  late final TextEditingController _base = TextEditingController(text: (((widget.rule['base_fare_minor'] as num?)?.toDouble() ?? 0) / 100).toStringAsFixed(2));
  late final TextEditingController _perKm = TextEditingController(text: (((widget.rule['per_km_minor'] as num?)?.toDouble() ?? 0) / 100).toStringAsFixed(2));
  late final TextEditingController _minimum = TextEditingController(text: (((widget.rule['minimum_fare_minor'] as num?)?.toDouble() ?? 0) / 100).toStringAsFixed(2));
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.rule['enabled'] as bool? ?? false;
  }

  @override
  void dispose() {
    _base.dispose();
    _perKm.dispose();
    _minimum.dispose();
    super.dispose();
  }

  void _save() {
    final base = double.tryParse(_base.text.trim());
    final perKm = double.tryParse(_perKm.text.trim());
    final minimum = double.tryParse(_minimum.text.trim());
    if (base == null || perKm == null || minimum == null || base < 0 || perKm < 0 || minimum < 0) {
      _toast(context, 'Enter valid non-negative INR amounts.');
      return;
    }
    Navigator.of(context).pop({
      'base_fare_minor': (base * 100).round(),
      'per_km_minor': (perKm * 100).round(),
      'minimum_fare_minor': (minimum * 100).round(),
      'enabled': _enabled,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Edit ' + _value(widget.rule, 'category') + ' fare'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _base, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Base fare (INR)')),
            TextField(controller: _perKm, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Per kilometre (INR)')),
            TextField(controller: _minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Minimum fare (INR)')),
            SwitchListTile(value: _enabled, onChanged: (v) => setState(() => _enabled = v), title: const Text('Fare category enabled')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save fares')),
        ],
      );
}

class _PlansTab extends StatefulWidget {
  const _PlansTab();

  @override
  State<_PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<_PlansTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _areas = [];
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _db.from('service_areas').select('id,code,name,active').order('code'),
        _db.from('subscription_plans').select().order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _areas = List<Map<String, dynamic>>.from(results[0]);
        _plans = List<Map<String, dynamic>>.from(results[1]);
      });
    } catch (error) {
      if (mounted) _toast(context, 'Could not load subscription plans.');
      debugPrint('Plan load failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _areaNameFor(String? id) {
    for (final area in _areas) {
      if (area['id'].toString() == id) return _value(area, 'name');
    }
    return 'Area';
  }

  Future<void> _editPlan([Map<String, dynamic>? plan]) async {
    if (_areas.isEmpty) {
      _toast(context, 'Create a service area first.');
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PlanEditor(areas: _areas, plan: plan),
    );
    if (result == null) return;
    try {
      final id = plan?['id']?.toString();
      if (id == null) {
        await _db.from('subscription_plans').insert({...result, 'created_by': _db.auth.currentUser?.id, 'updated_by': _db.auth.currentUser?.id});
      } else {
        await _db.from('subscription_plans').update({...result, 'updated_by': _db.auth.currentUser?.id}).eq('id', id);
      }
      if (mounted) _toast(context, 'Subscription plan saved.');
      await _load();
    } catch (error) {
      if (mounted) _toast(context, 'Could not save plan. Check price, duration and area.');
      debugPrint('Plan save failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(child: Text('Driver subscription plans', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                FilledButton.icon(onPressed: _loading ? null : () => _editPlan(), icon: const Icon(Icons.add), label: const Text('Add plan')),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Plans are area-specific and can be changed without releasing a new APK. Existing subscriptions retain the price and duration snapshot from purchase time.'),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            for (final plan in _plans)
              Card(
                child: ListTile(
                  leading: Icon(plan['active'] == true ? Icons.card_membership : Icons.pause_circle_outline),
                  title: Text(_value(plan, 'name')),
                  subtitle: Text(
                    _areaNameFor(plan['area_id']?.toString()) +
                    ' · ' + _value(plan, 'currency', 'INR') + ' ' +
                    (((plan['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2) +
                    ' · ' + (((plan['duration_minutes'] as num?)?.toInt() ?? 1440) / 60).toStringAsFixed(1) + ' hours' +
                    (plan['active'] == true ? ' · Active' : ' · Inactive'),
                  ),
                  trailing: IconButton(onPressed: () => _editPlan(plan), icon: const Icon(Icons.edit_outlined)),
                ),
              ),
            if (!_loading && _plans.isEmpty) const ListTile(title: Text('No plans created yet.')),
          ],
        ),
      );
}

class _PlanEditor extends StatefulWidget {
  const _PlanEditor({required this.areas, this.plan});
  final List<Map<String, dynamic>> areas;
  final Map<String, dynamic>? plan;

  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  late String _areaId = _value(widget.plan ?? {}, 'area_id', widget.areas.first['id'].toString());
  late final TextEditingController _name = TextEditingController(text: _value(widget.plan ?? {}, 'name', '24-hour driver pass'));
  late final TextEditingController _description = TextEditingController(text: _value(widget.plan ?? {}, 'description', ''));
  late final TextEditingController _price = TextEditingController(text: (((widget.plan?['price_minor'] as num?)?.toDouble() ?? 5000) / 100).toStringAsFixed(2));
  late final TextEditingController _hours = TextEditingController(text: (((widget.plan?['duration_minutes'] as num?)?.toInt() ?? 1440) / 60).round().toString());
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _active = widget.plan?['active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _hours.dispose();
    super.dispose();
  }

  void _save() {
    final price = double.tryParse(_price.text.trim());
    final hours = int.tryParse(_hours.text.trim());
    if (_name.text.trim().length < 2 || price == null || price < 0 || hours == null || hours < 1 || hours > 8760) {
      _toast(context, 'Enter a valid plan name, price and duration (1–8760 hours).');
      return;
    }
    Navigator.of(context).pop({
      'area_id': _areaId,
      'service': 'ride',
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'price_minor': (price * 100).round(),
      'currency': 'INR',
      'duration_minutes': hours * 60,
      'active': _active,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.plan == null ? 'Create subscription plan' : 'Edit subscription plan'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _areaId,
                  decoration: const InputDecoration(labelText: 'Service area'),
                  items: widget.areas.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(_value(a, 'name') + ' (' + _value(a, 'code') + ')'))).toList(),
                  onChanged: (v) => setState(() => _areaId = v ?? _areaId),
                ),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Plan name')),
                TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
                TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price in INR')),
                TextField(controller: _hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration in hours')),
                SwitchListTile(value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Plan active')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save plan')),
        ],
      );
}

class _AiReportsTab extends StatefulWidget {
  const _AiReportsTab();

  @override
  State<_AiReportsTab> createState() => _AiReportsTabState();
}

class _AiReportsTabState extends State<_AiReportsTab> {
  bool _loading = true;
  String _provider = 'none';
  bool _enabled = false;
  bool _daily = false;
  int _interval = 24;
  int _maxRequests = 1000;
  late final TextEditingController _model = TextEditingController();
  late final TextEditingController _budget = TextEditingController(text: '1000');
  late final TextEditingController _requestCost = TextEditingController(text: '0.10');
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _usage = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _model.dispose();
    _budget.dispose();
    _requestCost.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await _db.from('ai_runtime_settings').select().eq('singleton', true).maybeSingle();
      final reports = await _db.from('daily_ai_reports').select('id,period_start,period_end,status,summary,provider,model,findings,recommendations,created_at,error_code').order('created_at', ascending: false).limit(20);
      final usage = await _db.from('ai_usage_events').select('id,job_type,provider,model,status,estimated_cost_minor,created_at,error_code').order('created_at', ascending: false).limit(20);
      if (!mounted) return;
      setState(() {
        _provider = _value(settings ?? {}, 'provider', 'none');
        _enabled = settings?['enabled'] as bool? ?? false;
        _daily = settings?['daily_report_enabled'] as bool? ?? false;
        _interval = (settings?['report_interval_hours'] as num?)?.toInt() ?? 24;
        _maxRequests = (settings?['max_requests_per_day'] as num?)?.toInt() ?? 1000;
        _budget.text = (((settings?['max_cost_minor_per_day'] as num?)?.toDouble() ?? 100000) / 100).toStringAsFixed(0);
        _requestCost.text = (((settings?['estimated_cost_minor_per_request'] as num?)?.toDouble() ?? 10) / 100).toStringAsFixed(2);
        _model.text = settings?['model']?.toString() ?? '';
        _reports = List<Map<String, dynamic>>.from(reports);
        _usage = List<Map<String, dynamic>>.from(usage);
      });
    } catch (error) {
      if (mounted) _toast(context, 'Could not load AI settings or reports.');
      debugPrint('AI settings load failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final budget = double.tryParse(_budget.text.trim());
    final requestCost = double.tryParse(_requestCost.text.trim());
    if (budget == null || budget < 0 || requestCost == null || requestCost < 0 || _maxRequests < 1 || _interval < 1 || _interval > 168) {
      _toast(context, 'Check report interval, request limit and daily budget.');
      return;
    }
    setState(() => _loading = true);
    try {
      await _db.from('ai_runtime_settings').update({
        'provider': _provider,
        'model': _model.text.trim().isEmpty ? null : _model.text.trim(),
        'enabled': _enabled,
        'daily_report_enabled': _daily,
        'report_interval_hours': _interval,
        'max_requests_per_day': _maxRequests,
        'max_cost_minor_per_day': (budget * 100).round(),
        'estimated_cost_minor_per_request': (requestCost * 100).round(),
        'updated_by': _db.auth.currentUser?.id,
      }).eq('singleton', true);
      if (mounted) _toast(context, 'AI settings saved. API keys remain in Supabase Edge Function secrets.');
      await _load();
    } catch (error) {
      if (mounted) _toast(context, 'Could not save AI settings.');
      debugPrint('AI settings save failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('AI operations settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Choose one provider. API keys are not stored in the database or app; add them later as Supabase Edge Function secrets. The reporting function is deployed but requires its cron secret and provider credentials before it can run.'),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
              value: _provider,
              decoration: const InputDecoration(labelText: 'AI provider'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Disabled / no provider')),
                DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
                DropdownMenuItem(value: 'anthropic', child: Text('Anthropic Claude')),
              ],
              onChanged: _loading ? null : (v) => setState(() => _provider = v ?? 'none'),
            ),
            TextField(controller: _model, decoration: const InputDecoration(labelText: 'Provider model ID', helperText: 'Use a model enabled for your API account.')),
            SwitchListTile(value: _enabled, onChanged: _loading ? null : (v) => setState(() => _enabled = v), title: const Text('Enable AI features')),
            SwitchListTile(value: _daily, onChanged: _loading ? null : (v) => setState(() => _daily = v), title: const Text('Enable daily AI report')),
            DropdownButtonFormField<int>(
              value: _interval,
              decoration: const InputDecoration(labelText: 'Report interval'),
              items: const [1, 6, 12, 24, 48, 72].map((h) => DropdownMenuItem(value: h, child: Text(h.toString() + ' hours'))).toList(),
              onChanged: _loading ? null : (v) => setState(() => _interval = v ?? 24),
            ),
            DropdownButtonFormField<int>(
              value: _maxRequests,
              decoration: const InputDecoration(labelText: 'Maximum AI requests per day'),
              items: const [100, 500, 1000, 5000, 10000].map((n) => DropdownMenuItem(value: n, child: Text(n.toString()))).toList(),
              onChanged: _loading ? null : (v) => setState(() => _maxRequests = v ?? 1000),
            ),
            TextField(controller: _budget, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Maximum AI spend per day (INR)')),
            TextField(controller: _requestCost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Estimated cost per AI request (INR)', helperText: 'Budget enforcement uses this estimate; verify actual spend in the provider console.')),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _loading ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Save AI settings')),
            const Divider(height: 32),
            const Text('Latest daily reports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final report in _reports)
              Card(
                child: ExpansionTile(
                  leading: Icon(report['status'] == 'succeeded' ? Icons.check_circle_outline : report['status'] == 'failed' ? Icons.error_outline : Icons.schedule),
                  title: Text(_value(report, 'status').toUpperCase() + ' · ' + _value(report, 'provider', 'none')),
                  subtitle: Text(_value(report, 'period_start') + ' → ' + _value(report, 'period_end')),
                  children: [
                    Padding(padding: const EdgeInsets.all(16), child: Align(alignment: Alignment.centerLeft, child: Text(_value(report, 'summary', 'No summary available.')))),
                    if (report['error_code'] != null) ListTile(title: const Text('Error code'), subtitle: Text(report['error_code'].toString())),
                  ],
                ),
              ),
            if (!_loading && _reports.isEmpty) const ListTile(title: Text('No reports yet.')),
            const Divider(height: 32),
            const Text('Recent AI budget events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final event in _usage)
              ListTile(
                leading: Icon(event['status'] == 'succeeded' ? Icons.check_circle_outline : event['status'] == 'failed' ? Icons.error_outline : Icons.schedule),
                title: Text(_value(event, 'job_type') + ' · ' + _value(event, 'provider') + ' · ' + _value(event, 'status')),
                subtitle: Text(_value(event, 'created_at') + (event['error_code'] == null ? '' : ' · ' + event['error_code'].toString())),
                trailing: Text('~ INR ' + (((event['estimated_cost_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2)),
              ),
            if (!_loading && _usage.isEmpty) const ListTile(title: Text('No AI usage recorded yet.')),
          ],
        ),
      );
}

class _OperationsTab extends StatefulWidget {
  const _OperationsTab();

  @override
  State<_OperationsTab> createState() => _OperationsTabState();
}

class _OperationsTabState extends State<_OperationsTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _applications = [];
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _subscriptions = [];
  List<Map<String, dynamic>> _rides = [];
  List<Map<String, dynamic>> _drivers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _db.from('driver_applications').select('id,user_id,full_name,phone,vehicle_category,vehicle_make_model,vehicle_registration,status,created_at').order('created_at', ascending: false).limit(50),
        _db.from('support_tickets').select('id,subject,message,status,needs_human,priority,ai_attempt_count,created_at').order('created_at', ascending: false).limit(50),
        _db.from('driver_subscriptions').select('id,driver_id,area_id,plan_id,status,price_minor_snapshot,currency,created_at').eq('status', 'pending_payment').order('created_at', ascending: false).limit(50),
        _db.from('rides').select('id,customer_id,driver_id,status,category,fare_minor,currency,created_at,service_area_id,business_model_snapshot').eq('status', 'searching').order('created_at', ascending: false).limit(50),
        _db.from('driver_profiles').select('user_id,display_name,status,rating').eq('status', 'available').limit(100),
      ]);
      if (!mounted) return;
      setState(() {
        _applications = List<Map<String, dynamic>>.from(results[0]);
        _tickets = List<Map<String, dynamic>>.from(results[1]);
        _subscriptions = List<Map<String, dynamic>>.from(results[2]);
        _rides = List<Map<String, dynamic>>.from(results[3]);
        _drivers = List<Map<String, dynamic>>.from(results[4]);
      });
    } catch (error) {
      if (mounted) _toast(context, 'Could not load operations. Check admin RLS policies.');
      debugPrint('Operations load failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(Map<String, dynamic> application, String decision) async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(decision == 'approved' ? 'Approve driver application?' : 'Reject driver application?'),
        content: TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Review note (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(decision == 'approved' ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (confirmed != true) {
      note.dispose();
      return;
    }
    try {
      await _db.rpc('admin_review_driver_application', params: {
        'p_application_id': application['id'],
        'p_decision': decision,
        'p_review_note': note.text.trim(),
      });
      if (mounted) _toast(context, 'Application ' + decision + '.');
      await _load();
    } catch (error) {
      if (mounted) _toast(context, 'Could not review application. Check vehicle registration uniqueness and admin role.');
      debugPrint('Driver review failed: $error');
    } finally {
      note.dispose();
    }
  }

  Future<void> _updateTicket(Map<String, dynamic> ticket) async {
    final status = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Update support ticket'),
        children: [
          for (final s in const ['in_progress', 'resolved', 'closed'])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, s), child: Text(s.replaceAll('_', ' '))),
        ],
      ),
    );
    if (status == null) return;
    try {
      await _db.rpc('admin_update_support_ticket', params: {
        'p_ticket_id': ticket['id'],
        'p_status': status,
        'p_priority': ticket['priority'] ?? 'normal',
        'p_note': '',
      });
      if (mounted) _toast(context, 'Support ticket updated.');
      await _load();
    } catch (error) {
      if (mounted) _toast(context, 'Could not update ticket.');
      debugPrint('Ticket update failed: $error');
    }
  }

  Future<void> _activateSubscription(Map<String, dynamic> subscription) async {
    final reference = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activate subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Only continue after you have verified the actual payment. For manual UPI/cash, enter a receipt or transaction reference.'),
            TextField(controller: reference, decoration: const InputDecoration(labelText: 'Payment / receipt reference')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verify and activate')),
        ],
      ),
    );
    if (confirmed != true) {
      reference.dispose();
      return;
    }
    try {
      await _db.rpc('admin_activate_subscription', params: {
        'p_subscription_id': subscription['id'],
        'p_payment_reference': reference.text.trim(),
      });
      if (mounted) _toast(context, 'Subscription activated.');
      await _load();
    } catch (error) {
      if (mounted) _toast(context, 'Could not activate. Verify payment reference and subscription status.');
      debugPrint('Subscription activation failed: $error');
    } finally {
      reference.dispose();
    }
  }

  Future<void> _assignDriver(Map<String, dynamic> ride) async {
    if (_drivers.isEmpty) {
      _toast(context, 'No drivers are currently available.');
      return;
    }
    final driverId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Assign available driver'),
        children: _drivers.map((driver) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, driver['user_id'].toString()),
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(_value(driver, 'display_name', 'Driver')),
            subtitle: Text('Rating ' + _value(driver, 'rating', '5.0')),
          ),
        )).toList(),
      ),
    );
    if (driverId == null) return;
    try {
      await _db.rpc('admin_assign_driver_to_ride', params: {
        'p_ride_id': ride['id'],
        'p_driver_id': driverId,
      });
      if (mounted) _toast(context, 'Driver assigned.');
      await _load();
    } catch (error) {
      if (mounted) _toast(context, 'Assignment failed. Check driver availability and subscription eligibility.');
      debugPrint('Ride assignment failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(child: Text('Operations queue', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            const Text('Sensitive changes use database RPCs that enforce the admin role and write audit events.'),
            if (_loading) const LinearProgressIndicator(),
            const Divider(height: 28),
            const Text('Driver applications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final app in _applications.where((a) => a['status'] == 'pending' || a['status'] == 'in_review'))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_value(app, 'full_name'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(_value(app, 'phone') + ' · ' + _value(app, 'vehicle_category')),
                      Text(_value(app, 'vehicle_make_model') + ' · ' + _value(app, 'vehicle_registration')),
                      Row(
                        children: [
                          TextButton(onPressed: _loading ? null : () => _review(app, 'rejected'), child: const Text('Reject')),
                          const Spacer(),
                          FilledButton(onPressed: _loading ? null : () => _review(app, 'approved'), child: const Text('Approve')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (!_loading && _applications.isEmpty) const ListTile(title: Text('No driver applications waiting for review.')),
            const Divider(height: 28),
            const Text('Support escalations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final ticket in _tickets)
              Card(
                child: ListTile(
                  leading: Icon(ticket['priority'] == 'urgent' ? Icons.warning_amber : Icons.support_agent),
                  title: Text(_value(ticket, 'subject')),
                  subtitle: Text(_value(ticket, 'message') + '\nStatus: ' + _value(ticket, 'status') + ' · Priority: ' + _value(ticket, 'priority', 'normal') + ' · AI attempts: ' + _value(ticket, 'ai_attempt_count', '0') + (ticket['needs_human'] == true ? ' · HUMAN REVIEW' : '')),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (_) => _updateTicket(ticket),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'update', child: Text('Update status')),
                    ],
                  ),
                ),
              ),
            if (!_loading && _tickets.isEmpty)
              const ListTile(title: Text('No support tickets recorded.')),
            const Divider(height: 28),
            const Text('Pending subscriptions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final subscription in _subscriptions)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.pending_actions),
                  title: Text('Driver ' + _value(subscription, 'driver_id').substring(0, 8)),
                  subtitle: Text('Amount: ' + _value(subscription, 'currency', 'INR') + ' ' + (((subscription['price_minor_snapshot'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2)),
                  trailing: TextButton(onPressed: _loading ? null : () => _activateSubscription(subscription), child: const Text('Activate')),
                ),
              ),
            if (!_loading && _subscriptions.isEmpty) const ListTile(title: Text('No pending subscriptions.')),
            const Divider(height: 28),
            const Text('Searching rides', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final ride in _rides)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.local_taxi),
                  title: Text(_value(ride, 'category') + ' · ' + _value(ride, 'status')),
                  subtitle: Text('Fare: ' + _value(ride, 'currency', 'INR') + ' ' + (((ride['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2) + ' · Model: ' + _value(ride, 'business_model_snapshot')),
                  trailing: TextButton(onPressed: _loading ? null : () => _assignDriver(ride), child: const Text('Assign')),
                ),
              ),
            if (!_loading && _rides.isEmpty) const ListTile(title: Text('No rides waiting for assignment.')),
          ],
        ),
      );
}
