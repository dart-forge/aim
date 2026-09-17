/// Cookie support for Aim framework with secure options.
///
/// Provides `setCookie`, `getCookie`, `cookies`, and `deleteCookie`
/// extension methods on `Context` to write and read cookies, with options
/// like HttpOnly, Secure, SameSite, and expiration on the way out.
///
/// Example:
/// ```dart
/// import 'package:aim_server/aim_server.dart';
/// import 'package:aim_server_cookie/aim_server_cookie.dart';
///
/// void main() {
///   final app = Aim();
///
///   app.get('/login', (c) {
///     c.setCookie('session_id', 'abc123', options: CookieOptions(
///       httpOnly: true,
///       secure: true,
///       maxAge: Duration(hours: 24),
///       sameSite: SameSite.strict,
///     ));
///     return c.json({'status': 'logged in'});
///   });
///
///   app.get('/profile', (c) {
///     final sessionId = c.getCookie('session_id');
///     return c.json({'sessionId': sessionId});
///   });
///
///   app.listen(port: 3000);
/// }
/// ```
library;

export 'src/aim_server_cookie.dart';
export 'src/cookie_options.dart';
