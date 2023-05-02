/// Signature of callbacks that have no arguments and return no data.
typedef VoidCallback = void Function();

/// {@template data}
/// A wrapper for some value of type [T] that makes it easy to distinguish
/// between `null` as valid instance of [T] and `null` as not present.
///
/// This class is mainly used to distinguish between loading and ready states.
/// Used in combination with `Wrapped<T>?`, `null` indicates loading,
/// while `Wrapped<T>` indicates ready.
///
/// This is preferred over `T?`, as `T?` is not as type-safe: `null` could be
/// interpreted as either a valid instance of `T` or as not present
/// (e.g. loading value). The `T?` approach would be good only with
/// non-nullable [T]; using [Wrapped] every nullable type is supported.
/// {@endtemplate}
class Wrapped<T> {
  /// {@macro data}
  const Wrapped(T value) : _value = value;

  final T _value;

  /// Unwraps the data held by the instance.
  ///
  /// If [T] is non-nullable, it is fine to do:
  ///
  /// ```dart
  /// try {
  ///   final nullableValue = userResourceState.wrappedData?.unwrap;
  ///   // If nullableValue is null, it is in loading state.
  /// } catch (e) {
  ///   // in error state
  /// }
  /// ```
  ///
  /// On the other hand, if [T] is nullable, you should not use the snippet
  /// above, as the `null` case would be ambiguous. Instead, do:
  ///
  /// ```dart
  /// try {
  ///   final wrapped = userResourceState.wrappedData;
  ///   if (wrapped == null) {
  ///     // in loading state
  ///   } else {
  ///     // in data state
  ///   }
  /// } catch (e) {
  ///   // in error state
  /// }
  /// ```
  T get unwrap => _value;
}
