import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class FareQuote {
  const FareQuote({required this.id, required this.category, required this.amountMinor, required this.currency, required this.etaSeconds, required this.expiresAt});
  final String id;
  final String category;
  final int amountMinor;
  final String currency;
  final int etaSeconds;
  final DateTime expiresAt;

  factory FareQuote.fromMap(Map<String, dynamic> m) => FareQuote(
    id: m['quote_id'].toString(),
    category: m['category'].toString(),
    amountMinor: (m['amount_minor'] as num).toInt(),
    currency: m['currency'].toString().trim(),
    etaSeconds: (m['eta_seconds'] as num).toInt(),
    expiresAt: DateTime.parse(m['expires_at'].toString()).toUtc(),
  );
}

class RideRecord {
  const RideRecord({required this.id, required this.status, required this.sequence, required this.category, required this.amountMinor, required this.currency, required this.pickup, required this.destination, required this.createdAt});
  final String id;
  final String status;
  final int sequence;
  final String category;
  final int amountMinor;
  final String currency;
  final GeoPoint pickup;
  final GeoPoint destination;
  final DateTime createdAt;

  factory RideRecord.fromMap(Map<String, dynamic> m) => RideRecord(
    id: m['id'].toString(),
    status: m['status'].toString(),
    sequence: (m['seq'] as num).toInt(),
    category: m['category'].toString(),
    amountMinor: (m['fare_minor'] as num).toInt(),
    currency: m['currency'].toString().trim(),
    pickup: GeoPoint((m['pickup_lat'] as num).toDouble(), (m['pickup_lng'] as num).toDouble()),
    destination: GeoPoint((m['destination_lat'] as num).toDouble(), (m['destination_lng'] as num).toDouble()),
    createdAt: DateTime.parse(m['created_at'].toString()).toUtc(),
  );
}

class RideBackend {
  RideBackend(this.client);
  final SupabaseClient client;
  static const _uuid = Uuid();
  final Map<String, String> _createKeys = <String, String>{};

  Future<List<FareQuote>> estimate(GeoPoint pickup, GeoPoint destination) async {
    final data = await client.rpc('estimate_fares', params: {
      'p_pickup_lat': pickup.latitude,
      'p_pickup_lng': pickup.longitude,
      'p_destination_lat': destination.latitude,
      'p_destination_lng': destination.longitude,
    });
    return (data as List).map((e) => FareQuote.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<RideRecord> createRide({required FareQuote quote, required String pickupLabel, required String destinationLabel}) async {
    final data = await client.rpc('create_ride', params: {
      'p_quote_id': quote.id,
      'p_idempotency_key': _createKeys.putIfAbsent(quote.id, () => _uuid.v4()),
      'p_pickup_label': pickupLabel,
      'p_destination_label': destinationLabel,
    });
    return RideRecord.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<RideRecord?> activeRide() async {
    final user = client.auth.currentUser;
    if (user == null) return null;
    final row = await client.from('rides').select().eq('customer_id', user.id)
      .inFilter('status', ['searching', 'driver_assigned', 'driver_arriving', 'driver_arrived', 'otp_required', 'in_trip'])
      .order('created_at', ascending: false).limit(1).maybeSingle();
    return row == null ? null : RideRecord.fromMap(row);
  }

  Future<RideRecord> cancelRide(String rideId) async {
    final data = await client.rpc('cancel_ride', params: {
      'p_ride_id': rideId,
      'p_idempotency_key': _uuid.v4(),
      'p_reason': 'customer_request',
    });
    return RideRecord.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Stream<List<Map<String, dynamic>>> rideEvents(String rideId) =>
    client.from('ride_events').stream(primaryKey: ['id']).eq('ride_id', rideId);
}
