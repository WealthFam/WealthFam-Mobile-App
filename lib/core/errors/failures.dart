abstract class Failure {
  final String message;
  const Failure([this.message = 'An unexpected error occurred']);

  @override
  String toString() => message;
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error occurred']);
}

class ConnectionFailure extends Failure {
  const ConnectionFailure([super.message = 'Connectivity error. Check your internet.']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Local storage error occurred']);
}

class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Validation failed']);
}

class SecurityFailure extends Failure {
  const SecurityFailure([super.message = 'Authentication or security error occurred']);
}
