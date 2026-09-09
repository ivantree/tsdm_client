/// Decodes the signed redirect emitted by the Discuz browser challenge.
String? decodeDiscuzDsignRedirect(String script) {
  try {
    final statements = _Parser(_Lexer(script).tokenize()).parseProgram();
    final redirects = <String>[];
    final browser = _BrowserContext(redirects);
    final scope = _Scope()
      ..define('location', browser.location)
      ..define('window', browser.window);

    _execute(statements, scope, null);
    for (final redirect in redirects) {
      final uri = Uri.tryParse(redirect);
      if (uri?.queryParameters['_dsign'] case final String dsign when dsign.isNotEmpty) {
        return redirect;
      }
    }
  } on FormatException {
    return null;
  }
  return null;
}

enum _TokenType { identifier, string, symbol, end }

class _Token {
  const _Token(this.type, this.value);

  final _TokenType type;
  final String value;
}

class _Lexer {
  _Lexer(this.source);

  final String source;
  var _index = 0;

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    while (_index < source.length) {
      final char = source[_index];
      if (_isWhitespace(char)) {
        _index++;
        continue;
      }
      if (char == '/' && _peek('/')) {
        _skipLineComment();
        continue;
      }
      if (char == '/' && _peek('*')) {
        _skipBlockComment();
        continue;
      }
      if (char == "'" || char == '"') {
        tokens.add(_Token(_TokenType.string, _readString(char)));
        continue;
      }
      if (_isIdentifierStart(char) || _isDigit(char)) {
        tokens.add(_Token(_TokenType.identifier, _readIdentifier()));
        continue;
      }
      tokens.add(_Token(_TokenType.symbol, char));
      _index++;
    }
    return [...tokens, const _Token(_TokenType.end, '')];
  }

  bool _peek(String expected) => _index + 1 < source.length && source[_index + 1] == expected;

  void _skipLineComment() {
    _index += 2;
    while (_index < source.length && source[_index] != '\n') {
      _index++;
    }
  }

  void _skipBlockComment() {
    _index += 2;
    while (_index + 1 < source.length && !(source[_index] == '*' && source[_index + 1] == '/')) {
      _index++;
    }
    _index = (_index + 2).clamp(0, source.length);
  }

  String _readString(String quote) {
    _index++;
    final result = StringBuffer();
    while (_index < source.length) {
      final char = source[_index++];
      if (char == quote) {
        return result.toString();
      }
      if (char != r'\' || _index >= source.length) {
        result.write(char);
        continue;
      }
      final escaped = source[_index++];
      switch (escaped) {
        case 'n':
          result.write('\n');
        case 'r':
          result.write('\r');
        case 't':
          result.write('\t');
        case 'x':
          result.write(_readHexEscape(2));
        case 'u':
          result.write(_readHexEscape(4));
        default:
          result.write(escaped);
      }
    }
    throw const FormatException('unterminated JavaScript string');
  }

  String _readHexEscape(int length) {
    if (_index + length > source.length) {
      throw const FormatException('invalid JavaScript escape');
    }
    final value = int.tryParse(source.substring(_index, _index + length), radix: 16);
    _index += length;
    if (value == null) {
      throw const FormatException('invalid JavaScript escape');
    }
    return String.fromCharCode(value);
  }

  String _readIdentifier() {
    final start = _index;
    while (_index < source.length) {
      final char = source[_index];
      if (!_isIdentifierPart(char) && !_isDigit(char)) {
        break;
      }
      _index++;
    }
    return source.substring(start, _index);
  }

  static bool _isWhitespace(String char) => ' \t\r\n'.contains(char);

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static bool _isIdentifierStart(String char) {
    final code = char.codeUnitAt(0);
    return code == 36 || code == 95 || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  static bool _isIdentifierPart(String char) => _isIdentifierStart(char);
}

sealed class _Statement {}

class _ExpressionStatement extends _Statement {
  _ExpressionStatement(this.expression);

  final _Expression expression;
}

class _FunctionDeclaration extends _Statement {
  _FunctionDeclaration(this.name, this.parameters, this.body, {this.isGetName = false});

  final String name;
  final List<String> parameters;
  final List<_Statement> body;
  final bool isGetName;
}

class _VariableDeclaration extends _Statement {
  _VariableDeclaration(this.name, this.initializer);

  final String name;
  final _Expression? initializer;
}

class _ReturnStatement extends _Statement {
  _ReturnStatement(this.expression);

  final _Expression? expression;
}

sealed class _Expression {}

class _StringExpression extends _Expression {
  _StringExpression(this.value);

  final String value;
}

class _IdentifierExpression extends _Expression {
  _IdentifierExpression(this.name);

  final String name;
}

class _FunctionExpression extends _Expression {
  _FunctionExpression(this.name, this.parameters, this.body);

  final String? name;
  final List<String> parameters;
  final List<_Statement> body;
}

class _ConcatExpression extends _Expression {
  _ConcatExpression(this.left, this.right);

  final _Expression left;
  final _Expression right;
}

class _CallExpression extends _Expression {
  _CallExpression(this.callee, this.arguments);

  final _Expression callee;
  final List<_Expression> arguments;
}

class _MemberExpression extends _Expression {
  _MemberExpression(this.target, this.member);

  final _Expression target;
  final _Expression member;
}

class _AssignmentExpression extends _Expression {
  _AssignmentExpression(this.target, this.value);

  final _Expression target;
  final _Expression value;
}

class _UnknownExpression extends _Expression {}

class _Parser {
  _Parser(this.tokens);

  final List<_Token> tokens;
  var _index = 0;

  List<_Statement> parseProgram() => _parseStatements(untilClosingBrace: false);

  List<_Statement> _parseStatements({required bool untilClosingBrace}) {
    final statements = <_Statement>[];
    while (!_isAtEnd && !(untilClosingBrace && _check('}'))) {
      if (_match(';')) {
        continue;
      }
      statements.add(_parseStatement());
      _match(';');
    }
    if (untilClosingBrace) {
      _expect('}');
    }
    return statements;
  }

  _Statement _parseStatement() {
    if (_matchIdentifier('function')) {
      final name = _expectIdentifier();
      final parameters = _parseParameters();
      if (name == 'getName') {
        _skipBlock();
        return _FunctionDeclaration(name, parameters, const [], isGetName: true);
      }
      return _FunctionDeclaration(name, parameters, _parseBlock());
    }
    if (_matchIdentifier('var')) {
      final name = _expectIdentifier();
      final initializer = _match('=') ? _parseAssignment() : null;
      return _VariableDeclaration(name, initializer);
    }
    if (_matchIdentifier('return')) {
      final expression = _check(';') || _check('}') ? null : _parseAssignment();
      return _ReturnStatement(expression);
    }
    return _ExpressionStatement(_parseAssignment());
  }

  List<String> _parseParameters() {
    _expect('(');
    final parameters = <String>[];
    if (!_check(')')) {
      do {
        parameters.add(_expectIdentifier());
      } while (_match(','));
    }
    _expect(')');
    return parameters;
  }

  List<_Statement> _parseBlock() {
    _expect('{');
    return _parseStatements(untilClosingBrace: true);
  }

  void _skipBlock() {
    _expect('{');
    var depth = 1;
    while (!_isAtEnd && depth > 0) {
      final token = _advance();
      if (token.value == '{') {
        depth++;
      } else if (token.value == '}') {
        depth--;
      }
    }
    if (depth != 0) {
      throw const FormatException('unterminated JavaScript block');
    }
  }

  _Expression _parseAssignment() {
    final target = _parseConcatenation();
    if (_match('=')) {
      return _AssignmentExpression(target, _parseAssignment());
    }
    return target;
  }

  _Expression _parseConcatenation() {
    var expression = _parsePostfix();
    while (_match('+')) {
      expression = _ConcatExpression(expression, _parsePostfix());
    }
    return expression;
  }

  _Expression _parsePostfix() {
    var expression = _parsePrimary();
    while (true) {
      if (_match('(')) {
        final arguments = <_Expression>[];
        if (!_check(')')) {
          do {
            arguments.add(_parseAssignment());
          } while (_match(','));
        }
        _expect(')');
        expression = _CallExpression(expression, arguments);
      } else if (_match('.')) {
        expression = _MemberExpression(expression, _StringExpression(_expectIdentifier()));
      } else if (_match('[')) {
        final member = _parseAssignment();
        _expect(']');
        expression = _MemberExpression(expression, member);
      } else {
        return expression;
      }
    }
  }

  _Expression _parsePrimary() {
    final token = _advance();
    if (token.type == _TokenType.string) {
      return _StringExpression(token.value);
    }
    if (token.type == _TokenType.identifier) {
      if (token.value == 'function') {
        final name = _current.type == _TokenType.identifier ? _advance().value : null;
        final parameters = _parseParameters();
        return _FunctionExpression(name, parameters, _parseBlock());
      }
      return _IdentifierExpression(token.value);
    }
    if (token.value == '(') {
      final expression = _parseAssignment();
      _expect(')');
      return expression;
    }
    return _UnknownExpression();
  }

  bool _match(String value) {
    if (!_check(value)) {
      return false;
    }
    _index++;
    return true;
  }

  bool _matchIdentifier(String value) => _current.type == _TokenType.identifier && _match(value);

  bool _check(String value) => !_isAtEnd && _current.value == value;

  void _expect(String value) {
    if (!_match(value)) {
      throw FormatException('expected $value, found ${_current.value}');
    }
  }

  String _expectIdentifier() {
    if (_current.type != _TokenType.identifier) {
      throw FormatException('expected identifier, found ${_current.value}');
    }
    return _advance().value;
  }

  _Token _advance() => tokens[_index++];

  _Token get _current => tokens[_index];

  bool get _isAtEnd => _current.type == _TokenType.end;
}

class _Scope {
  _Scope([this.parent]);

  final _Scope? parent;
  final _values = <String, Object?>{};

  void define(String name, Object? value) => _values[name] = value;

  Object? get(String name) => _values.containsKey(name) ? _values[name] : parent?.get(name) ?? _unknown;

  void assign(String name, Object? value) {
    if (_values.containsKey(name) || parent == null) {
      _values[name] = value;
    } else {
      parent!.assign(name, value);
    }
  }
}

class _FunctionValue {
  _FunctionValue(this.name, this.parameters, this.body, this.closure);

  final String? name;
  final List<String> parameters;
  final List<_Statement> body;
  final _Scope closure;
}

class _NativeFunction {
  _NativeFunction(this.invoke);

  final Object? Function(List<Object?> arguments, String? callerName) invoke;
}

class _BrowserContext {
  _BrowserContext(List<String> redirects)
    : location = _BrowserObject(redirects, isLocation: true),
      window = _BrowserObject(redirects, isLocation: false) {
    window.location = location;
  }

  final _BrowserObject location;
  final _BrowserObject window;
}

class _BrowserObject {
  _BrowserObject(this.redirects, {required this.isLocation});

  final List<String> redirects;
  final bool isLocation;
  _BrowserObject? location;

  Object? getMember(String name) {
    if (!isLocation && name == 'location') {
      return location ?? _unknown;
    }
    if (name == 'assign' || name == 'replace') {
      return _NativeFunction((arguments, _) {
        _record(arguments.firstOrNull);
        return null;
      });
    }
    return _unknown;
  }

  void setMember(String name, Object? value) {
    if (name == 'href') {
      _record(value);
    }
  }

  void _record(Object? value) {
    if (value case final String redirect) {
      redirects.add(redirect);
    }
  }
}

class _ReturnValue {
  _ReturnValue(this.value);

  final Object? value;
}

const _unknown = _UnknownValue();

class _UnknownValue {
  const _UnknownValue();
}

_ReturnValue? _execute(List<_Statement> statements, _Scope scope, String? callerName) {
  for (final statement in statements.whereType<_FunctionDeclaration>()) {
    scope.define(
      statement.name,
      statement.isGetName
          ? _NativeFunction((_, callerName) => callerName ?? '')
          : _FunctionValue(statement.name, statement.parameters, statement.body, scope),
    );
  }

  for (final statement in statements) {
    switch (statement) {
      case _FunctionDeclaration():
        break;
      case _VariableDeclaration(:final name, :final initializer):
        scope.define(name, initializer == null ? null : _evaluate(initializer, scope, callerName));
      case _ExpressionStatement(:final expression):
        _evaluate(expression, scope, callerName);
      case _ReturnStatement(:final expression):
        return _ReturnValue(expression == null ? null : _evaluate(expression, scope, callerName));
    }
  }
  return null;
}

Object? _evaluate(_Expression expression, _Scope scope, String? callerName) => switch (expression) {
  _StringExpression(:final value) => value,
  _IdentifierExpression(:final name) => scope.get(name),
  _FunctionExpression(:final name, :final parameters, :final body) => _FunctionValue(name, parameters, body, scope),
  _ConcatExpression(:final left, :final right) => _concat(
    _evaluate(left, scope, callerName),
    _evaluate(right, scope, callerName),
  ),
  _CallExpression(:final callee, :final arguments) => _call(
    _evaluate(callee, scope, callerName),
    arguments.map((argument) => _evaluate(argument, scope, callerName)).toList(),
    callerName,
  ),
  _MemberExpression(:final target, :final member) => _getMember(
    _evaluate(target, scope, callerName),
    _evaluate(member, scope, callerName),
  ),
  _AssignmentExpression(:final target, :final value) => _assign(
    target,
    _evaluate(value, scope, callerName),
    scope,
    callerName,
  ),
  _UnknownExpression() => _unknown,
};

Object? _concat(Object? left, Object? right) => left is String && right is String ? '$left$right' : _unknown;

Object? _call(Object? callee, List<Object?> arguments, String? callerName) {
  if (callee case _NativeFunction(:final invoke)) {
    return invoke(arguments, callerName);
  }
  if (callee case _FunctionValue(:final name, :final parameters, :final body, :final closure)) {
    final local = _Scope(closure);
    for (var index = 0; index < parameters.length; index++) {
      local.define(parameters[index], index < arguments.length ? arguments[index] : _unknown);
    }
    return _execute(body, local, name)?.value;
  }
  return _unknown;
}

Object? _getMember(Object? target, Object? member) {
  if (target case _BrowserObject() when member is String) {
    return target.getMember(member);
  }
  return _unknown;
}

Object? _assign(_Expression target, Object? value, _Scope scope, String? callerName) {
  switch (target) {
    case _IdentifierExpression(:final name):
      scope.assign(name, value);
    case _MemberExpression(target: final object, member: final member):
      final evaluatedObject = _evaluate(object, scope, callerName);
      final evaluatedMember = _evaluate(member, scope, callerName);
      if (evaluatedObject case _BrowserObject() when evaluatedMember is String) {
        evaluatedObject.setMember(evaluatedMember, value);
      }
    default:
      break;
  }
  return value;
}
