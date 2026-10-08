import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride/core/error/failures.dart';
import 'package:go_ride/core/result/result.dart';
import 'package:go_ride/core/retry/retry_policy.dart';

void main() {
  group('RetryPolicy', () {
    test('Retries transient failure until success', () async {
      var attempts = 0;
      final result = await RetryPolicy.execute(() async {
        attempts++;
        return attempts == 3 ? const Success<bool, Failure>(true) : const Error<bool, Failure>(NetworkFailure('Drop'));
      }, maxAttempts: 3, delayProvider: (_) async {});
      expect(result, isA<Success<bool, Failure>>());
      expect(attempts, 3);
    });
    test('Halts on conflict', () async {
      var attempts = 0;
      final result = await RetryPolicy.execute(() async {
        attempts++;
        return const Error<bool, Failure>(ConflictFailure('State changed'));
      }, delayProvider: (_) async {});
      expect(result, isA<Error<bool, Failure>>());
      expect(attempts, 1);
    });
  });
}
