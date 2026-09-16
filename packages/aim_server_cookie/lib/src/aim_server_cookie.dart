import 'package:aim_core/aim_core.dart';
import 'package:aim_server_cookie/src/cookie_options.dart';

extension CookieContext on Context {
  /// Every cookie sent by the client on this request, keyed by name.
  ///
  /// Parses the request's `Cookie` header: pairs separated by `;`, each
  /// `name=value`, with whitespace around a pair trimmed. A pair with no
  /// `=` is skipped. When the same name appears twice, the first one wins,
  /// which is the order a browser sends the most specific cookie in.
  /// Values are percent-decoded to match the encoding [setCookie] applies
  /// when writing them. Returns an empty map when the request has no
  /// `Cookie` header at all.
  ///
  /// Example:
  /// ```dart
  /// app.get('/profile', (c) {
  ///   return c.json(c.cookies);
  /// });
  /// ```
  Map<String, String> get cookies {
    final header = headers['cookie'];
    if (header == null) return {};

    final result = <String, String>{};
    for (final rawPair in header.split(';')) {
      final pair = rawPair.trim();
      if (pair.isEmpty) continue;

      final separator = pair.indexOf('=');
      if (separator == -1) continue;

      final name = pair.substring(0, separator);
      if (result.containsKey(name)) continue;

      final value = pair.substring(separator + 1);
      result[name] = Uri.decodeComponent(value);
    }
    return result;
  }

  /// The value of the cookie named [name] on this request, or `null` when
  /// the request carries no cookie by that name.
  ///
  /// Example:
  /// ```dart
  /// app.get('/profile', (c) {
  ///   final sessionId = c.getCookie('session_id');
  ///   return c.text('Session: $sessionId');
  /// });
  /// ```
  String? getCookie(String name) => cookies[name];

  /// Sets a cookie in the response.
  ///
  /// Multiple cookies can be set by calling this method multiple times.
  ///
  /// [value] is percent-encoded before it is written, so it survives
  /// round-tripping through [cookies] / [getCookie] even when it contains
  /// characters such as `;`, `,`, whitespace, or a quote that would
  /// otherwise be ambiguous or invalid inside a `Set-Cookie` header.
  ///
  /// Example:
  /// ```dart
  /// app.get('/login', (c) {
  ///   c.setCookie('session_id', 'abc123', options: CookieOptions(
  ///     httpOnly: true,
  ///     secure: true,
  ///     maxAge: Duration(hours: 24),
  ///     sameSite: SameSite.strict,
  ///   ));
  ///   return c.json({'status': 'logged in'});
  /// });
  /// ```
  void setCookie(String name, String value, {CookieOptions? options}) {
    final cookieString = _buildCookieString(name, value, options);

    // Add to existing set-cookie header (joined by newline)
    final existing = responseHeaders['set-cookie'];
    if (existing != null) {
      header('set-cookie', '$existing\n$cookieString');
    } else {
      header('set-cookie', cookieString);
    }
  }

  /// Builds a Set-Cookie header value from name, value, and options.
  String _buildCookieString(String name, String value, CookieOptions? options) {
    final buffer = StringBuffer('$name=${Uri.encodeComponent(value)}');

    if (options != null) {
      if (options.path != null) {
        buffer.write('; Path=${options.path}');
      }
      if (options.domain != null) {
        buffer.write('; Domain=${options.domain}');
      }
      if (options.maxAge != null) {
        buffer.write('; Max-Age=${options.maxAge!.inSeconds}');
      }
      if (options.expires != null) {
        buffer.write('; Expires=${_formatHttpDate(options.expires!)}');
      }
      if (options.secure == true) {
        buffer.write('; Secure');
      }
      if (options.httpOnly == true) {
        buffer.write('; HttpOnly');
      }
      if (options.sameSite != null) {
        final sameSiteValue = _formatSameSite(options.sameSite!);
        buffer.write('; SameSite=$sameSiteValue');
      }
    }

    return buffer.toString();
  }

  /// Formats a DateTime to HTTP date format (RFC 1123).
  ///
  /// Example: "Wed, 21 Oct 2015 07:28:00 GMT"
  String _formatHttpDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final utc = date.toUtc();
    final weekday = weekdays[utc.weekday - 1];
    final month = months[utc.month - 1];

    return '$weekday, ${utc.day.toString().padLeft(2, '0')} $month ${utc.year} '
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')} GMT';
  }

  /// Formats SameSite enum to proper case.
  String _formatSameSite(SameSite sameSite) {
    switch (sameSite) {
      case SameSite.strict:
        return 'Strict';
      case SameSite.lax:
        return 'Lax';
      case SameSite.none:
        return 'None';
    }
  }

  /// Deletes a cookie by setting its Max-Age to 0.
  ///
  /// Note: To successfully delete a cookie, you must specify the same
  /// path and domain that were used when setting the cookie.
  ///
  /// Example:
  /// ```dart
  /// app.get('/logout', (c) async {
  ///   c.deleteCookie('session_id', path: '/');
  ///   return c.json({'status': 'logged out'});
  /// });
  /// ```
  void deleteCookie(String name, {String? path, String? domain}) {
    setCookie(
      name,
      '',
      options: CookieOptions(maxAge: Duration.zero, path: path, domain: domain),
    );
  }
}
