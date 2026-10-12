/// Client configuration only. The publishable key is not an authorization
/// mechanism; Supabase RLS and database grants enforce data access.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rwbavyjpzyzijjwgtyqv.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_Wk8biKlewkt9DiEgoVyy5g_Rw40cfks',
  );
}
