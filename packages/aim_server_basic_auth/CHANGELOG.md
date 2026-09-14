# Changelog

## 0.2.0

- **Breaking:** `BasicAuthEnv` is renamed to `BasicAuthVariables` (deprecated typedef kept for one release). `basicAuth()` now requires `E extends BasicAuthVariables`.

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1] - 2026-01-03

### Added

- Initial release of `aim_server_basic_auth`
- RFC 7617 compliant HTTP Basic Authentication middleware
- Custom async user verification function support
- Configurable realm for authentication dialogs
- Path exclusion feature for public routes
- Full support for special characters in passwords (including colons)
- Unicode character support in usernames and passwords
- Automatic WWW-Authenticate header in 401 responses
- Comprehensive test suite with 36 tests
- Complete API documentation with dartdoc comments
- Security best practices documentation
- Comparison guide with JWT authentication

### Security

- Enforces WWW-Authenticate header on all 401 responses (RFC 7617 compliance)
- Secure credential handling (passwords never logged or stored in middleware)
- Base64 decoding error handling
- Flexible verification function for custom security implementations

### Examples

- Basic authentication setup
- Database-backed user verification
- Password hashing integration
- Path exclusion configuration
- Production security recommendations
