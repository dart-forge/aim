---
title: Testing Guide - Aim Framework
description: Test Aim applications with official utilities. TestClient, response helpers, authentication testing, and best practices.
head:
  - - meta
    - name: keywords
      content: Dart testing, unit test, integration test, TestClient, Aim testing, Dart server testing
---

# Testing

Learn how to test your Aim applications with the official testing utilities.

## Testing Package

Aim provides `aim_server_testing` package with helpers and matchers for testing your applications.

```bash
dart pub add --dev aim_server_testing
```

## TestClient

The `TestClient` allows you to test your routes without starting a real server:

```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_testing/aim_server_testing.dart';
import 'package:test/test.dart';

void main() {
  test('GET / returns welcome message', () async {
    final app = Aim();

    app.get('/', (c) async {
      return c.json({'message': 'Welcome'});
    });

    final client = TestClient(app);
    final response = await client.get('/');

    expect(response.statusCode, equals(200));
    final body = await response.bodyAsJson();
    expect(body['message'], equals('Welcome'));
  });
}
```

## Making Requests

### GET Request

```dart
final response = await client.get('/users');
```

### POST Request

```dart
final response = await client.post(
  '/users',
  body: {'name': 'Alice', 'email': 'alice@example.com'},
);
```

### With Headers

```dart
final response = await client.get(
  '/protected',
  headers: {'Authorization': 'Bearer token123'},
);
```

### With Query Parameters

```dart
final response = await client.get('/search?q=dart&page=2');
```

## Response Helpers

### Status Code

```dart
expect(response.statusCode, equals(200));
expect(response.statusCode, equals(201));
expect(response.statusCode, equals(404));
```

### JSON Body

```dart
final body = await response.bodyAsJson();
expect(body['message'], equals('Success'));
```

### Text Body

```dart
final text = await response.bodyAsText();
expect(text, contains('Hello'));
```

### Headers

```dart
expect(response.headers['content-type'], equals('application/json'));
expect(response.headers['x-api-version'], equals('1.0'));
```

## Testing Middleware

```dart
test('Logger middleware logs requests', () async {
  final app = Aim();
  app.use(logger());

  app.get('/', (c) async => c.text('OK'));

  final client = TestClient(app);
  final response = await client.get('/');

  expect(response.statusCode, equals(200));
});
```

## Testing Authentication

```dart
import 'package:aim_server_jwt/aim_server_jwt.dart';

void main() {
  late Aim<JwtVariables> app;
  late TestClient client;

  setUp(() {
    app = Aim<JwtVariables>(
      variablesFactory: () => JwtVariables.create(
        JwtOptions(
          algorithm: HS256(
            secretKey: SecretKey(secret: 'test-secret-key-at-least-32-chars'),
          ),
          excludedPaths: ['/login'],
        ),
      ),
    );

    app.use(jwt());

    app.post('/login', (c) async {
      final token = Jwt(options: c.variables.jwtOptions).sign({
        'user_id': 123,
      });
      return c.json({'token': token});
    });

    app.get('/protected', (c) async {
      final payload = c.variables.jwtPayload;
      return c.json({'user_id': payload['user_id']});
    });

    client = TestClient(app);
  });

  test('Login returns token', () async {
    final response = await client.post('/login');

    expect(response.statusCode, equals(200));
    final body = await response.bodyAsJson();
    expect(body['token'], isNotNull);
  });

  test('Protected route requires auth', () async {
    final response = await client.get('/protected');
    expect(response.statusCode, equals(401));
  });

  test('Protected route with token succeeds', () async {
    // Get token
    final loginRes = await client.post('/login');
    final loginBody = await loginRes.bodyAsJson();
    final token = loginBody['token'];

    // Access protected route
    final response = await client.get(
      '/protected',
      headers: {'Authorization': 'Bearer $token'},
    );

    expect(response.statusCode, equals(200));
    final body = await response.bodyAsJson();
    expect(body['user_id'], equals(123));
  });
}
```

## Testing CORS

```dart
import 'package:aim_server_cors/aim_server_cors.dart';

test('CORS headers are set', () async {
  final app = Aim();

  app.use(cors(CorsOptions(
    origin: 'https://example.com',
    credentials: true,
  )));

  app.get('/api', (c) async => c.json({'data': 'value'}));

  final client = TestClient(app);
  final response = await client.get(
    '/api',
    headers: {'Origin': 'https://example.com'},
  );

  expect(
    response.headers['access-control-allow-origin'],
    equals('https://example.com'),
  );
  expect(
    response.headers['access-control-allow-credentials'],
    equals('true'),
  );
});
```

## Testing Error Handling

```dart
test('Returns 404 for unknown routes', () async {
  final app = Aim();

  app.get('/', (c) async => c.text('Home'));

  app.notFound((c) async {
    return c.json({'error': 'Not Found'}, statusCode: 404);
  });

  final client = TestClient(app);
  final response = await client.get('/unknown');

  expect(response.statusCode, equals(404));
  final body = await response.bodyAsJson();
  expect(body['error'], equals('Not Found'));
});
```

## Testing Form Data

`formData()` is an extension method on `Request`, not a middleware:

```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_form/aim_server_form.dart';
import 'package:aim_server_testing/aim_server_testing.dart';
import 'package:test/test.dart';

test('Form data is parsed', () async {
  final app = Aim();

  app.post('/submit', (c) async {
    final form = await c.req.formData();
    final name = form['name'];
    return c.json({'name': name});
  });

  final client = TestClient(app);
  final response = await client.post(
    '/submit',
    headers: {'content-type': 'application/x-www-form-urlencoded'},
    body: 'name=Alice',
  );

  expect(response.statusCode, equals(200));
  final body = await response.bodyAsJson();
  expect(body['name'], equals('Alice'));
});
```

## Best Practices

1. **Use setUp and tearDown**
   ```dart
   late Aim app;
   late TestClient client;

   setUp(() {
     app = Aim();
     // Configure app...
     client = TestClient(app);
   });
   ```

2. **Test error cases**
   ```dart
   test('Returns 400 for invalid input', () async {
     final response = await client.post('/users', body: {});
     expect(response.statusCode, equals(400));
   });
   ```

3. **Test different HTTP methods**
   ```dart
   test('GET returns list', () async { ... });
   test('POST creates resource', () async { ... });
   test('PUT updates resource', () async { ... });
   test('DELETE removes resource', () async { ... });
   ```

4. **Test middleware order**
   ```dart
   test('Auth middleware runs before handler', () async { ... });
   ```

5. **Test with realistic data**
   ```dart
   final userData = {
     'name': 'Alice',
     'email': 'alice@example.com',
     'age': 30,
   };
   ```

## Running Tests

```bash
# Run all tests
dart test

# Run specific file
dart test test/routes_test.dart

# Run with coverage
dart test --coverage=coverage
dart install coverage
format_coverage --lcov --in=coverage --out=coverage/lcov.info
```

## Next Steps

- Learn about [Best Practices](/server/guides/best-practices)
- Explore the [Context API](/server/concepts/context)
- Check out [Middleware testing](/server/concepts/middleware)
