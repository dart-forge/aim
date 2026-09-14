## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

### Major Refactoring
- **Simplified TestClient implementation**: Refactored to use `Aim.handle()` method instead of reimplementing middleware chain
  - Reduced code complexity by ~40% (253 lines → 145 lines)
  - Removed internal `_executeMiddlewareChain` method (~70 lines)
  - Improved maintainability by reducing dependency on Aim's internal implementation

### New Features

#### TestResponse Enhancements
- **Body caching**: Response body is now cached after first read (Stream can only be read once)
- **Detailed status code helpers** (properties):
  - `isOk` - 200 OK
  - `isCreated` - 201 Created
  - `isNoContent` - 204 No Content
  - `isBadRequest` - 400 Bad Request
  - `isUnauthorized` - 401 Unauthorized
  - `isForbidden` - 403 Forbidden
  - `isNotFound` - 404 Not Found
  - `isInternalServerError` - 500 Internal Server Error
- **JSON accessors**:
  - `jsonMap` - Get response body as JSON Map (cached)
  - `jsonList` - Get response body as JSON List (cached)

#### Custom Matchers
- **Specific status code matchers**:
  - `isOk()` - 200 OK
  - `isCreated()` - 201 Created
  - `isNoContent()` - 204 No Content
  - `isBadRequest()` - 400 Bad Request
  - `isUnauthorized()` - 401 Unauthorized
  - `isForbidden()` - 403 Forbidden
  - `isNotFound()` - 404 Not Found
  - `isInternalServerError()` - 500 Internal Server Error

### Breaking Changes
- **Removed test_middleware.dart**: Removed internal testing utilities that were not useful for application developers
  - Removed `SpyMiddleware`, `ExecutionTracker`, `conditionalMiddleware`, `timeoutMiddleware`, `headerMiddleware`, `errorThrowingMiddleware`, `mockAuthMiddleware`
  - Focus shifted to core testing functionality: `TestClient`, `TestRequestBuilder`, and matchers

### Dependencies
- Updated `aim_server` dependency from `0.0.4` to `0.0.5`

### Migration Guide

#### Body Caching
No migration needed. Body methods now cache automatically:
```dart
final response = await client.get('/data');
final body1 = await response.bodyAsString(); // Reads from stream
final body2 = await response.bodyAsString(); // Returns cached value
```

#### New Status Helpers
Use new convenience helpers instead of `hasStatus()`:
```dart
// Before
expect(response, hasStatus(200));
expect(response, hasStatus(201));

// After (more readable)
expect(response, isOk());
expect(response, isCreated());

// Or use properties
expect(response.isOk, isTrue);
expect(response.isCreated, isTrue);
```

#### Removed Test Middleware
If you were using test middleware helpers, replace them with custom implementations:
```dart
// SpyMiddleware replacement (if needed)
final callCount = 0;
app.use((c, next) async {
  callCount++;
  await next();
});
```

## 0.0.1

Initial release of aim_server_testing - Testing utilities for the Aim framework.

### Features

- **TestClient**: Test Aim applications without starting an HTTP server
  - Support for all HTTP methods: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
  - Custom headers and query parameters
  - JSON and text body support

- **TestRequestBuilder**: Fluent API for building test requests
  - Method chaining for headers, query parameters, and body
  - JSON and text body support

- **Custom Matchers**: Convenient matchers for response validation
  - `hasStatus(int statusCode)` - Status code validation
  - `hasHeader(String name, String value)` - Header validation
  - `isSuccessful()` - 2xx status codes
  - `isClientError()` - 4xx status codes
  - `isServerError()` - 5xx status codes

- **TestResponse**: Wrapper for Response with helper methods
  - `bodyAsString()` - Get body as string
  - `bodyAsJson()` - Parse body as JSON
  - `header(name)` - Get specific header
  - Status check properties: `isSuccessful`, `isClientError`, `isServerError`

### Dependencies
- `aim_server: ^0.0.6`
- `test: ^1.25.6`
