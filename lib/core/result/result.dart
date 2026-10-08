import '../error/failures.dart';

sealed class Result<S, F extends Failure> {
  const Result();
  T fold<T>(T Function(S success) onSuccess, T Function(F failure) onFailure);
}
class Success<S, F extends Failure> extends Result<S, F> {
  final S value;
  const Success(this.value);
  @override
  T fold<T>(T Function(S success) onSuccess, T Function(F failure) onFailure) => onSuccess(value);
}
class Error<S, F extends Failure> extends Result<S, F> {
  final F failure;
  const Error(this.failure);
  @override
  T fold<T>(T Function(S success) onSuccess, T Function(F failure) onFailure) => onFailure(failure);
}
