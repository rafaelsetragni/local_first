part of '../../local_first.dart';

/// A simple broadcast stream that replays the latest value to new listeners.
class ValueStream<T> {
  ValueStream()
      : _controller = StreamController<T>.broadcast(
          onListen: () {},
        );

  final StreamController<T> _controller;
  T? _latest;
  bool _hasValue = false;

  Stream<T> get stream {
    return _controller.stream.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (value, sink) => sink.add(value),
        handleDone: (sink) => sink.close(),
        handleError: (error, stackTrace, sink) =>
            sink.addError(error, stackTrace),
      ),
    ).asBroadcastStream(onListen: (sub) {
      if (_hasValue) {
        _controller.add(_latest as T);
      }
    });
  }

  void add(T value) {
    _latest = value;
    _hasValue = true;
    _controller.add(value);
  }

  void addError(Object error, [StackTrace? st]) =>
      _controller.addError(error, st);

  Future<void> close() => _controller.close();
}
