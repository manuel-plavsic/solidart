import 'dart:async';

import 'package:meta/meta.dart';
import 'package:solidart/src/core/signal.dart';
import 'package:solidart/src/core/signal_options.dart';
import 'package:solidart/src/utils.dart';

/// {@macro streamresource}
StreamResource<T> createStreamResource<T>(
  Stream<T> stream, {
  Wrapped<T> Function()? initialData,
  bool lazy = true,
  bool? cancelOnError,
  SignalOptions<StreamResourceValue<T>>? options,
}) {
  return StreamResource<T>(
    stream,
    initialData: initialData,
    lazy: lazy,
    cancelOnError: cancelOnError,
    options: options,
  );
}

/// {@template streamresource}
/// `StreamResources` are special `Signal`s designed specifically to handle
/// streams. Their purpose is wrap async values in a way that makes them easy
/// to interact with handling the common states of a future __data__, __error__
/// and __loading__.
///
/// Let's create a StreamResource:
///
/// ```dart
/// // Using http as a client
/// import 'package:http/http.dart' as http;
///
/// // The resource (source is optional)
/// final user = createResource(fetcher: fetchUser, source: userId);
/// ```
///
/// A Resource can also be driven from a [stream] instead of a Future.
/// In this case you just need to pass the `stream` field to the
/// `createResource` method.
///
/// If you are using the `flutter_solidart` library, check
/// `ResourceBuilder` to learn how to react to the state of the resource in the
/// UI.
///
/// The resource has a value named `ResourceValue`, that provides many useful
/// convenience methods to correctly handle the state of the resource.
///
/// The `on` method forces you to handle all the states of a Resource
/// (_ready_, _error_ and _loading_).
/// The are also other convenience methods to handle only specific states:
/// - `on` forces you to handle all the states of a Resource
/// - `maybeOn` lets you decide which states to handle and provide an `orElse`
/// action for unhandled states
/// - `map` equal to `on` but gives access to the `ResourceValue` data class
/// - `maybeMap` equal to `maybeMap` but gives access to the `ResourceValue`
/// data class
/// - `isReady` indicates if the `Resource` is in the ready state
/// - `isLoading` indicates if the `Resource` is in the loading state
/// - `hasError` indicates if the `Resource` is in the error state
/// - `asReady` upcast `ResourceValue` into a `ResourceReady`, or return null if the `ResourceValue` is in loading/error state
/// - `asError` upcast `ResourceValue` into a `ResourceError`, or return null if the `ResourceValue` is in loading/ready state
/// - `value` attempts to synchronously get the value of `ResourceReady`
/// - `error` attempts to synchronously get the error of `ResourceError`
///
/// A [StreamResource] provides the [resolve] method and the [closed] getter.
///
/// The [StreamResource] subscribes to the [stream].
///
/// The default value of `cancelOnError` is the default value of
/// [Stream.listen]'s `cancelOnError` (false).
/// {@endtemplate}
class StreamResource<T> extends Signal<StreamResourceValue<T>> {
  /// {@macro streamresource}
  StreamResource(
    this.stream, {
    Wrapped<T> Function()? initialData,
    bool lazy = true,
    bool? cancelOnError,
    super.options,
  })  : _initialData = initialData,
        _cancelOnError = cancelOnError,
        super(StreamResourceValue<T>.unresolved()) {
    if (!lazy) {
      resolve(forceLoadingState: false);
    }
  }

  /// The stream used to retrieve data.
  final Stream<T> stream;
  StreamSubscription<T>? _streamSubscription;

  bool _closed = false;

  /// Whether or not the [stream] is closed.
  bool get closed => _closed;

  bool _resolved = false;

  /// Whether or not the [resolve] method was already called.
  /// If `true`, the [stream] is being listened to.
  bool get resolved => _resolved;

  final Wrapped<T> Function()? _initialData;

  final bool? _cancelOnError;

  /// Resolves the [StreamResource].
  ///
  /// Otherwise it starts listening to the [stream].
  ///
  /// This method must be called once during the life cycle of the resource.
  ///
  /// You may not use this method directly on Flutter apps because the
  /// operation is already performed by `ResourceBuilder`.
  @protected
  Future<void> resolve({required bool forceLoadingState}) async {
    assert(
      value is StreamResourceUnresolved<T>,
      """The resource has been already resolved, you can't resolve it more than once. Use `refetch()` instead if you want to refresh the value.""",
    );

    if (_resolved == false) {
      _resolved = true;
    }

    /// Starts listening to the [stream] provided.
    void listenToStream() {
      // TODO: add rxdart support
      value = !forceLoadingState && _initialData != null
          ? StreamResourceValue.ready(_initialData!.call().unwrap)
          : StreamResourceValue<T>.loading();
      _streamSubscription = stream.listen(
        (data) {
          value = StreamResourceValue<T>.ready(data);
        },
        onError: (Object error, StackTrace? stackTrace) {
          value = StreamResourceValue<T>.error(error, stackTrace: stackTrace);
        },
        onDone: () {
          _closed = true;
          value.map(
            ready: (ready) => ready._copyWith(
              closed: true,
              refreshing: false,
            ),
            error: (error) => error._copyWith(
              closed: true,
              refreshing: false,
            ),
            loading: (loading) => loading._copyWith(
              closed: true,
            ),
          );
        },
        cancelOnError: _cancelOnError,
      );
    }

    listenToStream();
  }

  /// Resets the stream subscription.
  ///
  /// Since a stream can be closed, the [StreamResource] instance can be reset
  /// so that new events can be emitted.
  ///
  /// If [forceLoadingState] is `false`, initial data will be used. However,
  /// aesthetically wise, [forceLoadingState] should be left to`true` in most
  /// cases.
  /// Displaying initial data after a stream of `data` and/or `error` states
  /// might confuse the end users. Initial data should be used
  /// only at the very start of the stream.
  void resetSubscription({bool forceLoadingState = true}) {
    if (_streamSubscription != null) {
      _streamSubscription!.cancel();
      _streamSubscription = null;
      _closed = false;
      value = StreamResourceValue<T>.unresolved();
      resolve(forceLoadingState: forceLoadingState);
    }
    // If [_streamSubscription] is null it means that the [stream] hasn't been
    // listened to yet, therefore we can just ignore this case.
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  String toString() =>
      '''StreamResource<$T>(value: $value, previousValue: $previousValue, options; $options)''';
}

/// {@template streamresourcevalue}
/// Manages all the different states of a [StreamResource]:
/// - [StreamResourceUnresolved]
/// - [StreamResourceReady]
/// - [StreamResourceLoading]
/// - [StreamResourceError]
/// {@endtemplate}
@sealed
@immutable
abstract class StreamResourceValue<T> {
  /// The initial state of a [StreamResourceValue].
  const factory StreamResourceValue.unresolved() = StreamResourceUnresolved<T>;

  /// Creates an [StreamResourceValue] with a data.
  ///
  /// The data can be `null`.
  const factory StreamResourceValue.ready(
    T data,
  ) = StreamResourceReady<T>;

  /// Creates an [StreamResourceValue] in loading state.
  ///
  /// Prefer always using this constructor with the `const` keyword.
  // coverage:ignore-start
  const factory StreamResourceValue.loading() = StreamResourceLoading<T>;
  // coverage:ignore-end

  /// Creates an [StreamResourceValue] in error state.
  ///
  /// The parameter [error] cannot be `null`.
  // coverage:ignore-start
  const factory StreamResourceValue.error(
    Object error, {
    StackTrace? stackTrace,
  }) = StreamResourceError<T>;
  // coverage:ignore-end

  /// {@macro streamresourcevalue}
  // const StreamResourceValue(this.isClosed);

  /// private mapper, so that classes inheriting [StreamResource] can specify
  /// their own [map] method with different parameters.
  R map<R>({
    required R Function(StreamResourceReady<T> ready) ready,
    required R Function(StreamResourceError<T> error) error,
    required R Function(StreamResourceLoading<T> loading) loading,
  });
}

/// Creates an [StreamResourceValue] in ready state with a data.
@immutable
class StreamResourceReady<T> implements StreamResourceValue<T> {
  /// Creates an [StreamResourceValue] with a data.
  const StreamResourceReady(
    this.value, {
    this.refreshing = false,
    this.closed = false,
  });

  /// The value currently exposed.
  final T value;

  /// Indicates if the data is being refreshed. Defaults to `false`.
  final bool refreshing;

  /// Indicates if the stream is closed.
  final bool closed;

  // coverage:ignore-start
  @override
  R map<R>({
    required R Function(StreamResourceReady<T> ready) ready,
    required R Function(StreamResourceError<T> error) error,
    required R Function(StreamResourceLoading<T> loading) loading,
  }) {
    return ready(this);
  }

  @override
  String toString() {
    return 'StreamResourceReady<$T>(value: $value, refreshing: $refreshing)';
  }

  @override
  bool operator ==(Object other) =>
      runtimeType == other.runtimeType &&
      other is StreamResourceReady<T> &&
      other.value == value &&
      other.refreshing == refreshing &&
      other.closed == closed;

  @override
  int get hashCode => Object.hash(
        runtimeType,
        value,
        refreshing,
        closed,
      );

  /// Convenience method to update the [refreshing] value of a [StreamResource].
  StreamResourceReady<T> _copyWith({
    Wrapped<T>? wrappedValue,
    bool? refreshing,
    bool? closed,
  }) {
    return StreamResourceReady(
      wrappedValue == null ? this.value : wrappedValue.unwrap,
      refreshing: refreshing ?? this.refreshing,
      closed: closed ?? this.closed,
    );
  }
  // coverage:ignore-end
}

/// {@template streamresourceloading}
/// Creates an [StreamResourceValue] in loading state.
///
/// Prefer always using this constructor with the `const` keyword.
/// {@endtemplate}
@immutable
class StreamResourceLoading<T> implements StreamResourceValue<T> {
  /// {@macro streamresourceloading}
  const StreamResourceLoading({
    this.closed = false,
  });

  /// Indicates if the stream is closed.
  final bool closed;

  // coverage:ignore-start
  @override
  R map<R>({
    required R Function(StreamResourceReady<T> ready) ready,
    required R Function(StreamResourceError<T> error) error,
    required R Function(StreamResourceLoading<T> loading) loading,
  }) {
    return loading(this);
  }

  @override
  String toString() {
    return 'StreamResourceLoading<$T>()';
  }

  @override
  bool operator ==(Object other) =>
      runtimeType == other.runtimeType &&
      other is StreamResourceLoading<T> &&
      other.closed == closed;

  @override
  int get hashCode => Object.hash(
        runtimeType,
        closed,
      );

  /// Convenience method to update the [refreshing] value of a [StreamResource].
  StreamResourceLoading<T> _copyWith({
    bool? closed,
  }) {
    return StreamResourceLoading(
      closed: closed ?? this.closed,
    );
  }
  // coverage:ignore-end
}

/// {@template streamresourceerror}
/// Creates an [StreamResourceValue] in error state.
///
/// The parameter [error] cannot be `null`.
/// {@endtemplate}
@immutable
class StreamResourceError<T> implements StreamResourceValue<T> {
  /// {@macro streamresourceerror}
  const StreamResourceError(
    this.error, {
    this.stackTrace,
    this.refreshing = false,
    this.closed = false,
  });

  /// The error.
  final Object error;

  /// The stackTrace of [error], optional.
  final StackTrace? stackTrace;

  /// Indicates if the data is being refreshed. Defaults to `false`.
  final bool refreshing;

  /// Indicates if the stream is closed.
  final bool closed;

  // coverage:ignore-start
  @override
  R map<R>({
    required R Function(StreamResourceReady<T> ready) ready,
    required R Function(StreamResourceError<T> error) error,
    required R Function(StreamResourceLoading<T> loading) loading,
  }) {
    return error(this);
  }

  @override
  String toString() {
    return 'StreamResourceError<$T>(error: $error, stackTrace: $stackTrace)';
  }

  @override
  bool operator ==(Object other) =>
      runtimeType == other.runtimeType &&
      other is StreamResourceError<T> &&
      other.error == error &&
      other.stackTrace == stackTrace &&
      other.refreshing == refreshing &&
      other.closed == closed;

  @override
  int get hashCode => Object.hash(
        runtimeType,
        error,
        stackTrace,
        refreshing,
        closed,
      );

  /// Convenience method to update the [refreshing] and [closed] values of a
  /// [StreamResource].
  StreamResourceError<T> _copyWith({
    Object? error,
    StackTrace? stackTrace,
    bool? refreshing,
    bool? closed,
  }) {
    return StreamResourceError(
      error ?? this.error,
      stackTrace: stackTrace ?? this.stackTrace,
      refreshing: refreshing ?? this.refreshing,
      closed: closed ?? this.closed,
    );
  }
  // coverage:ignore-end
}

/// {@template streamresourceunresolved}
/// Creates an [StreamResourceValue] in unresolved state.
/// {@endtemplate}
@immutable
class StreamResourceUnresolved<T> implements StreamResourceValue<T> {
  /// {@macro streamresourceunresolved}
  // ignore: avoid_positional_boolean_parameters
  const StreamResourceUnresolved();

  // coverage:ignore-start
  @override
  R map<R>({
    required R Function(StreamResourceReady<T> ready) ready,
    required R Function(StreamResourceError<T> error) error,
    required R Function(StreamResourceLoading<T> loading) loading,
  }) {
    throw Exception('Cannot map an unresolved resource');
  }

  @override
  String toString() {
    return 'StreamResourceUnresolved<$T>()';
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType;
  }

  @override
  int get hashCode => runtimeType.hashCode;
  // coverage:ignore-end
}

/// Some useful extension available on any [StreamResourceValue].
// coverage:ignore-start
extension StreamResourceExtensions<T> on StreamResourceValue<T> {
  /// Indicates if the resource is loading.
  bool get isLoading => this is StreamResourceLoading<T>;

  /// Indicates if the resource has an error.
  bool get hasError => this is StreamResourceError<T>;

  /// Indicates if the resource is ready.
  bool get isReady => this is StreamResourceReady<T>;

  /// Indicates if the resource is refreshing.
  bool get isRefreshing =>
      this is StreamResourceReady<T> && this.asReady!.isRefreshing ||
      this is StreamResourceError<T> && this.asReady!.isRefreshing;

  /// Upcast [StreamResourceValue] into a [StreamResourceReady], or return
  /// `null` if the [StreamResourceValue] is in loading/error state.
  StreamResourceReady<T>? get asReady {
    return map(
      ready: (r) => r,
      error: (_) => null,
      loading: (_) => null,
    );
  }

  /// Upcast [StreamResourceValue] into a [StreamResourceError], or return
  /// `null` if the [StreamResourceValue] is in ready/loading state.
  StreamResourceError<T>? get asError {
    return map(
      error: (e) => e,
      ready: (_) => null,
      loading: (_) => null,
    );
  }

  /// Attempts to synchronously get the value of [StreamResourceReady].
  ///
  /// On error, this will rethrow the error.
  /// If loading, will return `null`.
  Wrapped<T>? get wrappedValue {
    return map(
      ready: (r) => Wrapped(r.value),
      // ignore: only_throw_errors
      error: (r) => throw r.error,
      loading: (_) => null,
    );
  }

  /// Attempts to synchronously get the error of [StreamResourceError].
  ///
  /// On other states will return `null`.
  Object? get error {
    return map(
      error: (r) => r.error,
      ready: (_) => null,
      loading: (_) => null,
    );
  }

  /// Perform some actions based on the state of the [StreamResourceValue],
  /// or call [orElse] if the current state is not considered.
  R maybeMap<R>({
    required R Function() orElse,
    R Function(StreamResourceReady<T> ready)? ready,
    R Function(StreamResourceError<T> error)? error,
    R Function(StreamResourceLoading<T> loading)? loading,
  }) {
    return map(
      ready: (r) {
        if (ready != null) return ready(r);
        return orElse();
      },
      error: (d) {
        if (error != null) return error(d);
        return orElse();
      },
      loading: (l) {
        if (loading != null) return loading(l);
        return orElse();
      },
    );
  }

  /// Performs an action based on the state of the [StreamResourceValue].
  ///
  /// All cases are required.
  ///
  /// Note that
  R on<R>({
    required R Function(T data, bool refreshing, bool closed) ready,
    required R Function(
      Object error,
      StackTrace? stackTrace,
      bool refreshing,
      bool closed,
    )
        error,
    required R Function(bool closed) loading,
  }) {
    return map(
      ready: (r) => ready(r.value, r.refreshing, r.closed),
      error: (e) => error(e.error, e.stackTrace, e.refreshing, e.closed),
      loading: (l) => loading(l.closed),
    );
  }

  /// Performs an action based on the state of the [StreamResourceValue], or call
  /// [orElse] if the current state is not considered.
  R maybeOn<R>({
    required R Function(bool refreshing, bool closed) orElse,
    R Function(T data, bool refreshing, bool closed)? ready,
    R Function(
      Object error,
      StackTrace? stackTrace,
      bool refreshing,
      bool closed,
    )?
        error,
    R Function(bool closed)? loading,
  }) {
    return map(
      ready: (r) {
        if (ready != null) {
          return ready(
            r.value,
            r.refreshing,
            r.closed,
          );
        }
        return orElse(r.refreshing, r.closed);
      },
      error: (e) {
        if (error != null) {
          return error(
            e.error,
            e.stackTrace,
            e.refreshing,
            e.closed,
          );
        }
        return orElse(e.refreshing, e.closed);
      },
      loading: (l) {
        if (loading != null) return loading(l.closed);
        return orElse(false, l.closed);
      },
    );
  }
}
// coverage:ignore-end
