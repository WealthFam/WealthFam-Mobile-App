import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/errors/either.dart';
import 'package:mobile_app/core/errors/failures.dart';

mixin NetworkResilience {
  Future<Either<Failure, T>> callWithResilience<T>({
    required Future<http.Response> Function() call,
    required FutureOr<T> Function(dynamic data) onSuccess,
    int maxRetries = 2,
  }) async {
    int retries = 0;

    while (true) {
      try {
        final response = await call().timeout(const Duration(seconds: 15));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            return Right(await onSuccess(response.body));
          } catch (e) {
            return const Left(ValidationFailure('Parsing error'));
          }
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          return const Left(SecurityFailure('Unauthorized access'));
        }

        if (response.statusCode >= 500) {
          if (retries < maxRetries) {
            retries++;
            await Future<void>.delayed(Duration(seconds: retries * 2));
            continue;
          }
          return Left(ServerFailure('Error: ${response.statusCode}'));
        }
      } on SocketException {
        if (retries < maxRetries) {
          retries++;
          await Future<void>.delayed(Duration(seconds: retries * 2));
          continue;
        }
        return const Left(ConnectionFailure());
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    }
  }
}
