typedef Either<L, R> = _Either<L, R>;

abstract class _Either<L, R> {
  const _Either();

  T fold<T>(T Function(L left) fnL, T Function(R right) fnR);

  bool get isLeft => this is Left<L, R>;
  bool get isRight => this is Right<L, R>;
}

class Left<L, R> extends _Either<L, R> {
  final L value;
  const Left(this.value);

  @override
  T fold<T>(T Function(L left) fnL, T Function(R right) fnR) => fnL(value);
}

class Right<L, R> extends _Either<L, R> {
  final R value;
  const Right(this.value);

  @override
  T fold<T>(T Function(L left) fnL, T Function(R right) fnR) => fnR(value);
}

class Unit {
  const Unit();
}

const unit = Unit();
