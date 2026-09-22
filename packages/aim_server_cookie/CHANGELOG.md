## 0.4.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.4.0)

## 0.3.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.3.0)

## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

- Initial release of `aim_server_cookie` package
- Added `setCookie()` method for setting cookies with full option support:
  - Path and Domain control
  - Max-Age and Expires for expiration
  - HttpOnly flag for XSS protection
  - Secure flag for HTTPS-only cookies
  - SameSite attribute (Strict, Lax, None) for CSRF protection
- Added `deleteCookie()` method for easy cookie deletion
- Support for multiple cookies in a single response
- Automatic HTTP date formatting (RFC 1123)
- Type-safe `CookieOptions` configuration
- Complete example application demonstrating all features
