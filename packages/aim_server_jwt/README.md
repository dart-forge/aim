# aim_server_jwt

JWT authentication middleware for the Aim framework.

[Documentation](https://aim-dart.dev/server/auth/jwt) | [pub.dev](https://pub.dev/packages/aim_server_jwt)

## Overview

`aim_server_jwt` provides JWT authentication and authorization middleware for the Aim framework. It enables stateless authentication using JSON Web Tokens with full support for standard JWT claims (iss, sub, aud, exp, iat, nbf) and custom payload data. Features automatic Bearer token validation, secure-by-default 32-character minimum secret keys, and path exclusion for public routes. Currently supports HS256 algorithm.

## Installation

```yaml
dependencies:
  aim_server: ^0.4.0
  aim_server_jwt: ^0.4.0
```

## Documentation

For detailed usage, examples, and API reference, see the [documentation](https://aim-dart.dev/server/auth/jwt).
