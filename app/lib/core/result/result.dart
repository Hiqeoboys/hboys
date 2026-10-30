sealed class Result<T> {
  const Result();
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}

class Failure {
  const Failure(this.code, [this.message]);
  final String code;
  final String? message;

  @override
  String toString() => 'Failure($code${message != null ? ': $message' : ''})';
}
