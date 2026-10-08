import '../../core/error/failures.dart';
import '../../core/result/result.dart';
abstract class IAuthSessionProvider {
  Future<Result<String, Failure>> getValidToken();
}
