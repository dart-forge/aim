## 0.2.0

- **Breaking:** `JwtEnv` is renamed to `JwtVariables` (deprecated typedef kept for one release). `jwt()` now requires `E extends JwtVariables`.

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release - JWT authentication middleware for Aim framework

### Features

- **JWT authentication middleware**: Automatic Bearer token validation
- **Token generation**: Create JWT tokens with standard and custom claims
- **HMAC-SHA256 (HS256)**: Secure token signing with minimum 32-character secrets
- **Standard claims support**: Full support for iss, sub, aud, exp, iat, nbf claims
- **Automatic validation**: Signature verification, expiration, and claim validation
- **Path exclusion**: Skip authentication for specific routes (e.g., /login, /public)
- **Type-safe design**: Sealed class architecture with compile-time safety
- **Custom exception**: `JwtException` for clear error handling
- **Context integration**: JWT payload accessible via `c.variables.jwtPayload`

### Supported Algorithms

- ✅ **HS256** (HMAC-SHA256) - Symmetric key algorithm
- 🔜 **RS256** (RSA-SHA256) - Coming soon
- 🔜 **ES256** (ECDSA-SHA256) - Coming soon

### Examples

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_jwt/aim_server_jwt.dart';

void main() {
  final app = Aim<JwtEnv>(
    envFactory: () => JwtEnv.create(
      JwtOptions(
        algorithm: HS256(
          secretKey: SecretKey(secret: 'your-secret-key-at-least-32-chars'),
        ),
        excludedPaths: ['/login'],
      ),
    ),
  );

  // Apply JWT middleware
  app.use(jwt());

  // Login endpoint
  app.post('/login', (c) async {
    final jwt = Jwt(options: c.variables.jwtOptions);
    final token = jwt.sign({'user_id': 1, 'role': 'admin'});
    return c.json({'token': token});
  });

  // Protected endpoint
  app.get('/profile', (c) async {
    final payload = c.variables.jwtPayload;
    return c.json({
      'user_id': payload['user_id'],
      'role': payload['role'],
    });
  });

  app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

### Security

- Enforces RFC 7518 minimum secret length (32 characters for HS256)
- Automatic token expiration validation
- Signature verification on every request
- Bearer token format validation
- Standard JWT claims validation (iss, aud, exp, nbf)
