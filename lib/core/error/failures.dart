import 'package:equatable/equatable.dart';

sealed class Failure extends Equatable implements Exception {
  final String message;
  const Failure(this.message);
  @override
  List<Object> get props => [message];
}
class NetworkFailure extends Failure { const NetworkFailure(super.message); }
class TimeoutFailure extends Failure { const TimeoutFailure(super.message); }
class ServerFailure extends Failure { const ServerFailure(super.message); }
class ConflictFailure extends Failure { const ConflictFailure(super.message); }
class AuthFailure extends Failure { const AuthFailure(super.message); }
class ReconciliationFailure extends Failure { const ReconciliationFailure(super.message); }
class ValidationFailure extends Failure { const ValidationFailure(super.message); }
