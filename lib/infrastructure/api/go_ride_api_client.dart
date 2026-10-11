import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Safe, unauthenticated endpoints used to show whether Go-Ride's API is
/// configured and healthy. Ride commands must use authenticated contracts.
class GoRideApiClient {
  GoRideApiClient({
    http.Client? client,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 6),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = (baseUrl ?? const String.fromEnvironment(
          'GO_RIDE_API_BASE_URL',
        )).trim(),
        _timeout = timeout;

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final Duration _timeout;

  bool get isConfigured => _baseUrl.isNotEmpty;

  Uri _endpoint(String path) {
    final base = Uri.parse(_baseUrl);
    if (!base.hasScheme ||
        !base.hasAuthority ||
        (base.scheme != 'https' && base.scheme != 'http')) {
      throw const FormatException(
        'The configured Go-Ride API URL must be an absolute HTTP(S) URL.',
      );
    }
    return base.resolve(path);
  }

  Future<BackendReadiness> checkReadiness() async {
    if (!isConfigured) {
      return const BackendReadiness(
        configured: false,
        ready: false,
        message: 'Backend URL is not configured for this build.',
      );
    }

    try {
      final response = await _client
          .get(_endpoint('/health/ready'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return const BackendReadiness(
          configured: true,
          ready: true,
          message: 'Backend reports ready.',
        );
      }
      return BackendReadiness(
        configured: true,
        ready: false,
        message: 'Backend is not ready (HTTP ${response.statusCode}).',
      );
    } on FormatException {
      return const BackendReadiness(
        configured: true,
        ready: false,
        message: 'The configured backend URL is invalid.',
      );
    } catch (_) {
      return const BackendReadiness(
        configured: true,
        ready: false,
        message: 'Backend could not be reached. Check the URL and network.',
      );
    }
  }

  /// Capabilities are presentation hints only, never an authorization check.
  Future<Map<String, dynamic>> fetchCapabilities() async {
    if (!isConfigured) {
      throw StateError('Go-Ride API URL is not configured.');
    }
    final response = await _client
        .get(_endpoint('/v1/capabilities'))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw HttpException(
        'Capabilities request failed (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid capabilities response.');
    }
    return decoded;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class BackendReadiness {
  const BackendReadiness({
    required this.configured,
    required this.ready,
    required this.message,
  });

  final bool configured;
  final bool ready;
  final String message;
}
