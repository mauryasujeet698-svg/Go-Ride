import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride/infrastructure/api/go_ride_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GoRideApiClient', () {
    test('does not make a request when the API URL is missing', () async {
      var requested = false;
      final client = GoRideApiClient(
        baseUrl: '',
        client: MockClient((_) async {
          requested = true;
          return http.Response('', 200);
        }),
      );

      final readiness = await client.checkReadiness();

      expect(readiness.configured, isFalse);
      expect(readiness.ready, isFalse);
      expect(readiness.message, contains('not configured'));
      expect(requested, isFalse);
      client.close();
    });

    test('reports a healthy backend only for HTTP 200', () async {
      final client = GoRideApiClient(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          expect(request.url.path, '/health/ready');
          return http.Response('{"status":"ready"}', 200);
        }),
      );

      final readiness = await client.checkReadiness();

      expect(readiness.configured, isTrue);
      expect(readiness.ready, isTrue);
      expect(readiness.message, 'Backend reports ready.');
      client.close();
    });

    test('keeps a non-ready backend unavailable', () async {
      final client = GoRideApiClient(
        baseUrl: 'https://api.example.test',
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );

      final readiness = await client.checkReadiness();

      expect(readiness.configured, isTrue);
      expect(readiness.ready, isFalse);
      expect(readiness.message, contains('503'));
      client.close();
    });

    test('parses public capabilities without treating them as authorization', () async {
      final client = GoRideApiClient(
        baseUrl: 'https://api.example.test/v1/',
        client: MockClient((request) async {
          expect(request.url.path, '/v1/capabilities');
          return http.Response(
            jsonEncode({'bookingEnabled': false, 'paymentsEnabled': false}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final capabilities = await client.fetchCapabilities();

      expect(capabilities['bookingEnabled'], isFalse);
      expect(capabilities['paymentsEnabled'], isFalse);
      client.close();
    });
  });
}
