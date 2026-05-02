typedef Either<L, R> = _Either<L, R>;

abstract class _Either<L, R> {
  const _Either();

  T fold<T>(T Function(L left) fnL, T Function(R right) fnR);

  bool get isLeft => this is Left<L, R>;
  bool get isRight => this is Right<L, R>;
}

class Left<L, R> extends _Either<L, R> {
  const Left(this.value);
  final L value;

  @override
  T fold<T>(T Function(L left) fnL, T Function(R right) fnR) => fnL(value);
}

class Right<L, R> extends _Either<L, R> {
  const Right(this.value);
  final R value;

  @override
  T fold<T>(T Function(L left) fnL, T Function(R right) fnR) => fnR(value);
}

class Unit {
  const Unit();
}

const unit = Unit();
