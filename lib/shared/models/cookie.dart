part of 'models.dart';

/// Cookie types.
typedef Cookie = Map<String, dynamic>;

bool _containsDiscuzAuthCookie(Object? value) {
  if (value is Map) {
    return value.entries.any((entry) => '${entry.key}'.endsWith('_auth') || _containsDiscuzAuthCookie(entry.value));
  }
  if (value is Iterable) {
    return value.any(_containsDiscuzAuthCookie);
  }
  if (value is! String) {
    return false;
  }

  try {
    final decoded = jsonDecode(value);
    return (decoded is Map || decoded is Iterable) && _containsDiscuzAuthCookie(decoded);
  } on FormatException {
    return false;
  }
}

/// Whether [value] contains a Discuz authentication cookie key.
bool containsDiscuzAuthCookie(Object? value) => _containsDiscuzAuthCookie(value);
