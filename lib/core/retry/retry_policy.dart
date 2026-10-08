import '../error/failures.dart';
import '../result/result.dart';

typedef DelayProvider = Future<void> Function(Duration duration);

class RetryPolicy {
  static Future<Result<S, Failure>> execute<S>(
    Future<Result<S, Failure>> Function() action, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
    DelayProvider delayProvider = Future.delayed,
  }) async {
    if (maxAttempts < 1) throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be at least 1');
    int attempt = 0;
    Duration currentDelay = initialDelay;
    while (attempt < maxAttempts) {
      final result = await action();
      if (result is Success<S, Failure>) return result;
      final failure = (result as Error<S, Failure>).failure;
      if (failure is ConflictFailure || failure is AuthFailure ||
          failure is ValidationFailure || failure is ReconciliationFailure) {
        return result;
      }
      attempt++;
      if (attempt >= maxAttempts) return result;
      await delayProvider(currentDelay);
      currentDelay *= 2;
    }
    return const Error(TimeoutFailure('Retry policy exhausted.'));
  }
}
