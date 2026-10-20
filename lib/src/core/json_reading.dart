/// Small, typed helpers for reading decoded JSON.
///
/// `jsonDecode` returns `Object?`. Instead of casting blindly, every read goes
/// through one of these helpers, which checks the runtime type and turns a
/// mismatch into a [SaveException] that says which field was wrong.
library;

import 'dart:convert';

import 'save_exception.dart';

/// A decoded JSON object.
typedef JsonMap = Map<String, Object?>;

/// Decodes [source] and requires the top level to be a JSON object.
JsonMap decodeJsonObject(String source, {required String what}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw SaveException('$what is not valid JSON (${error.message}).');
  }
  return requireMap(decoded, what: what);
}

/// Returns [value] as a [JsonMap] or throws if it is anything else.
JsonMap requireMap(Object? value, {required String what}) {
  if (value is Map<String, Object?>) {
    return value;
  }
  throw SaveException('$what should be a JSON object.');
}

/// Returns [value] as a list or throws if it is anything else.
List<Object?> requireList(Object? value, {required String what}) {
  if (value is List<Object?>) {
    return value;
  }
  throw SaveException('$what should be a JSON list.');
}

/// Returns [value] as a string or throws if it is anything else.
String requireString(Object? value, {required String what}) {
  if (value is String) {
    return value;
  }
  throw SaveException('$what should be text.');
}

/// Returns [value] as a non-empty string, or `null` when it is missing,
/// empty or not a string at all. Used for optional fields.
String? optionalString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// Returns [value] as a number, or `null` when it is missing or not numeric.
num? optionalNum(Object? value) => value is num ? value : null;
