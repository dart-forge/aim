/// Splits a PostgreSQL one-dimensional array literal (`{1,"a b",NULL}`)
/// into its element strings.
///
/// Returns `null` for shapes this driver does not decode: nested arrays
/// (`{{1},{2}}`), arrays with explicit bounds (`[0:2]={...}`), or text that
/// is not an array literal at all. Callers treat `null` as "leave the value
/// as text". Quoted elements have their quotes and backslash escapes
/// removed; an unquoted `NULL` becomes `null`.
///
/// Throws [FormatException] on an unterminated quoted element.
List<String?>? parsePgArrayLiteral(String text) {
  if (text.length < 2 || text[0] != '{' || text[text.length - 1] != '}') {
    return null;
  }
  final body = text.substring(1, text.length - 1);
  if (body.isEmpty) return const [];

  final elements = <String?>[];
  final current = StringBuffer();
  var inQuotes = false;
  var currentWasQuoted = false;

  void finishElement() {
    final raw = current.toString();
    elements.add(!currentWasQuoted && raw == 'NULL' ? null : raw);
    current.clear();
    currentWasQuoted = false;
  }

  var i = 0;
  while (i < body.length) {
    final c = body[i];
    if (inQuotes) {
      if (c == r'\') {
        if (i + 1 >= body.length) {
          throw FormatException('Unterminated escape in array literal', text);
        }
        current.write(body[i + 1]);
        i += 2;
        continue;
      }
      if (c == '"') {
        inQuotes = false;
        i++;
        continue;
      }
      current.write(c);
      i++;
      continue;
    }
    switch (c) {
      case '"':
        inQuotes = true;
        currentWasQuoted = true;
      case '{':
        return null; // nested array
      case ',':
        finishElement();
      default:
        current.write(c);
    }
    i++;
  }
  if (inQuotes) {
    throw FormatException('Unterminated quote in array literal', text);
  }
  finishElement();
  return elements;
}
