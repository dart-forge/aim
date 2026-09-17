import 'package:aim_core/src/context.dart';
import 'package:aim_core/src/variables.dart';
import 'package:aim_core/src/request.dart';
import 'package:aim_core/src/response.dart';
import 'package:aim_core/src/route.dart';

/// A function that handles an HTTP request and returns a response.
///
/// Handlers are registered via [Aim.get], [Aim.post], etc.
typedef Handler<E extends Variables> = Future<Response> Function(Context<E> c);

/// A function that processes requests in a middleware chain.
///
/// Middleware can modify the context, perform actions before/after the handler,
/// or finalize the response early.
typedef Middleware<E extends Variables> = Future<void> Function(
  Context<E> c,
  Next next,
);

/// A function that handles errors that occur during request processing.
///
/// Error handlers are registered via [Aim.onError].
typedef ErrorHandler<E extends Variables> = Future<Response> Function(
  Object error,
  Context<E> c,
);

/// A function that calls the next middleware in the chain.
typedef Next = Future<void> Function();

/// A function that handles an error when no [Aim.onError] handler is
/// registered. Receives the stack trace so adapters can log it.
typedef UnhandledErrorHandler<E extends Variables> = Future<Response> Function(
  Object error,
  StackTrace stackTrace,
  Context<E> c,
);

/// A modern, simple, and fast web framework for Dart.
///
/// Aim provides an intuitive API for building HTTP servers with support for:
/// - Routing with path parameters and wildcards
/// - Middleware
/// - Type-safe context variables
/// - CORS handling
///
/// Example:
/// ```dart
/// final app = Aim();
/// app.get('/hello', (c) async => c.text('Hello, World!'));
/// // See `aim_server` for `serve()`.
/// ```
class Aim<E extends Variables> {
  final List<Route<E>> _routes = [];
  final List<Middleware<E>> _middlewares = [];

  /// Get an unmodifiable list of all registered routes.
  ///
  /// This is useful for generating OpenAPI specifications, documentation, etc.
  List<Route<E>> get routes => List.unmodifiable(_routes);

  /// Get an unmodifiable list of all registered middlewares.
  ///
  /// This is useful for testing and debugging purposes.
  List<Middleware<E>> get middlewares => List.unmodifiable(_middlewares);

  /// Handler for 404 Not Found responses
  Handler<E>? _notFoundHandler;

  /// Handler for error responses
  ErrorHandler<E>? _errorHandler;

  /// Factory function to create instances of [E].
  ///
  /// This must be provided by the user when using a custom [Variables].
  final E Function() _variablesFactory;

  /// Creates a new [Aim] instance.
  ///
  /// If using a custom [Variables], provide a [variablesFactory] that creates instances of [E].
  ///
  /// Example:
  /// ```dart
  /// final app = Aim<MyVariables>(variablesFactory: () => MyVariables());
  /// ```
  Aim({E Function()? variablesFactory})
    : _variablesFactory = variablesFactory ?? (() => EmptyVariables() as E);

  /// Handles a request and returns a response without any HTTP layer.
  ///
  /// This is the single request-processing path. Runtime adapters
  /// (`aim_server`, `aim_edge`) build a [Request], call this method, and
  /// write the returned [Response] back to their platform.
  ///
  /// This method:
  /// 1. Creates a Context with the provided request
  /// 2. Finds a matching route based on request method and path
  /// 3. Executes the middleware chain
  /// 4. Calls the appropriate handler (route handler or 404 handler)
  /// 5. Handles errors using the registered error handler, then
  ///    [onUnhandledError], then a plain 500 response. The fallback to
  ///    [onUnhandledError] and the plain 500 also runs when the registered
  ///    error handler itself throws.
  ///
  /// The core never prints. Adapters that want to log unhandled errors pass
  /// [onUnhandledError].
  Future<Response> handle(
    Request request, {
    UnhandledErrorHandler<E>? onUnhandledError,
  }) async {
    final variables = _variablesFactory();
    final context = Context<E>(request, variables);

    try {
      Route<E>? matchingRoute;
      Map<String, String>? pathParams;

      for (final route in _routes) {
        if (route.method == request.method || route.method == '*') {
          final params = route.match(request.path);
          if (params != null) {
            matchingRoute = route;
            pathParams = params;
            break;
          }
        }
      }

      Handler<E> finalHandler;
      if (matchingRoute == null) {
        finalHandler =
            _notFoundHandler ??
            (c) async => Response.notFound(body: 'Not Found');
      } else {
        finalHandler = (c) async {
          pathParams!.forEach((key, value) {
            c.set('param:$key', value);
          });
          return await matchingRoute!.handler(c);
        };
      }

      return await _executeMiddlewareChain(context, finalHandler);
    } catch (e, st) {
      if (_errorHandler != null) {
        try {
          return await _errorHandler!(e, context);
        } catch (handlerError, handlerStack) {
          if (onUnhandledError != null) {
            try {
              return await onUnhandledError(
                handlerError,
                handlerStack,
                context,
              );
            } catch (_) {
              // fall through to the plain 500 below
            }
          }
          return Response.internalServerError(body: 'Internal Server Error');
        }
      }
      if (onUnhandledError != null) {
        try {
          return await onUnhandledError(e, st, context);
        } catch (_) {
          return Response.internalServerError(body: 'Internal Server Error');
        }
      }
      return Response.internalServerError(body: 'Internal Server Error: $e');
    }
  }

  /// Registers a GET route.
  ///
  /// The [path] can include parameters (e.g., `/users/:id`) and wildcards (e.g., `/files/*`).
  ///
  /// Example:
  /// ```dart
  /// app.get('/users/:id', (c) async {
  ///   final id = c.param('id');
  ///   return c.json({'userId': id});
  /// });
  /// ```
  Aim<E> get(String path, Handler<E> handler, {Object? metadata}) {
    _routes.add(
      Route<E>(path: path, method: 'GET', handler: handler, metadata: metadata),
    );
    return this;
  }

  /// Registers a POST route.
  ///
  /// Example:
  /// ```dart
  /// app.post('/users', (c) async {
  ///   final data = await c.req.json();
  ///   return c.json({'message': 'User created', 'user': data});
  /// });
  /// ```
  Aim<E> post(String path, Handler<E> handler, {Object? metadata}) {
    _routes.add(
      Route<E>(
        path: path,
        method: 'POST',
        handler: handler,
        metadata: metadata,
      ),
    );
    return this;
  }

  /// Registers a PUT route.
  Aim<E> put(String path, Handler<E> handler, {Object? metadata}) {
    _routes.add(
      Route<E>(path: path, method: 'PUT', handler: handler, metadata: metadata),
    );
    return this;
  }

  /// Registers a DELETE route.
  Aim<E> delete(String path, Handler<E> handler, {Object? metadata}) {
    _routes.add(
      Route<E>(
        path: path,
        method: 'DELETE',
        handler: handler,
        metadata: metadata,
      ),
    );
    return this;
  }

  /// Registers a PATCH route.
  Aim<E> patch(String path, Handler<E> handler, {Object? metadata}) {
    _routes.add(
      Route<E>(
        path: path,
        method: 'PATCH',
        handler: handler,
        metadata: metadata,
      ),
    );
    return this;
  }

  /// Registers a HEAD route.
  Aim<E> head(String path, Handler<E> handler, {Object? metadata}) {
    _routes.add(
      Route<E>(
        path: path,
        method: 'HEAD',
        handler: handler,
        metadata: metadata,
      ),
    );
    return this;
  }

  /// Registers an OPTIONS route.
  Aim<E> options(String path, Handler<E> handler, {Object? metadata}) {
    _routes.add(
      Route<E>(
        path: path,
        method: 'OPTIONS',
        handler: handler,
        metadata: metadata,
      ),
    );
    return this;
  }

  /// Registers a single route that answers every HTTP method on [path].
  ///
  /// This registers one route with the sentinel method `'*'`, not one
  /// route per known verb, so it also answers methods Aim has no named
  /// method for (e.g. `TRACE`), and [routes] reports exactly one entry
  /// for it.
  ///
  /// Precedence follows the same rule as every other route: the first
  /// matching route in declaration order wins. A `get` (or any other
  /// verb) declared before an `all` on the same path still handles its
  /// own method; an `all` declared first handles everything, including
  /// that verb.
  ///
  /// Example:
  /// ```dart
  /// app.all('/webhook', (c) async {
  ///   final method = c.req.method;
  ///   return c.json({'received': method});
  /// });
  /// ```
  Aim<E> all(String path, Handler<E> handler, {Object? metadata}) {
    _routes.add(
      Route<E>(path: path, method: '*', handler: handler, metadata: metadata),
    );
    return this;
  }

  /// Registers a middleware function.
  ///
  /// Middleware is executed globally before route handlers.
  /// Middleware can modify the context, perform logging, authentication, etc.
  ///
  /// Example:
  /// ```dart
  /// app.use((c, next) async {
  ///   print('${c.method} ${c.path}');
  ///   await next();
  /// });
  /// ```
  Aim<E> use(Middleware<E> middleware) {
    _middlewares.add(middleware);
    return this;
  }

  /// Sets a custom handler for 404 Not Found responses.
  ///
  /// This handler is called when no route matches the request.
  ///
  /// Example:
  /// ```dart
  /// app.notFound((c) async {
  ///   return c.json({'error': 'Not Found'}, statusCode: 404);
  /// });
  /// ```
  Aim<E> notFound(Handler<E> handler) {
    _notFoundHandler = handler;
    return this;
  }

  /// Sets a custom error handler for uncaught exceptions.
  ///
  /// This handler is called when an error occurs during request processing.
  ///
  /// Example:
  /// ```dart
  /// app.onError((error, c) async {
  ///   print('Error: $error');
  ///   return c.json({'error': error.toString()}, statusCode: 500);
  /// });
  /// ```
  Aim<E> onError(ErrorHandler<E> handler) {
    _errorHandler = handler;
    return this;
  }

  /// Mounts a sub-application at the specified path prefix.
  ///
  /// All routes from the sub-application will be prefixed with [basePath].
  /// Middlewares from the sub-application are NOT automatically applied.
  ///
  /// Example:
  /// ```dart
  /// final api = Aim<MyVariables>(variablesFactory: () => MyVariables());
  /// api.get('/users', (c) => c.json({'users': []}));
  /// api.get('/posts', (c) => c.json({'posts': []}));
  ///
  /// final app = Aim<MyVariables>(variablesFactory: () => MyVariables());
  /// app.route('/api/v1', api); // Mounts at /api/v1/users, /api/v1/posts
  /// ```
  Aim<E> route(String basePath, Aim<E> subApp) {
    // Normalize base path (remove trailing slash)
    final normalizedBasePath = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;

    // Add all routes from sub-app with prefix
    for (final route in subApp._routes) {
      final prefixedPath = normalizedBasePath + route.path;
      _routes.add(
        Route<E>(
          path: prefixedPath,
          method: route.method,
          handler: route.handler,
        ),
      );
    }

    return this;
  }

  /// Executes middleware chain including the final handler.
  ///
  /// This implements koa-compose style middleware chaining where:
  /// - Middlewares can run code before calling next() (before phase)
  /// - The final handler is executed when all middlewares call next()
  /// - Middlewares can run code after next() returns (after phase)
  ///
  /// This allows middlewares to access the response after the handler executes.
  Future<Response> _executeMiddlewareChain(
    Context<E> context,
    Handler<E> finalHandler,
  ) async {
    var index = -1;

    Future<Response> dispatch(int i) async {
      if (i <= index) {
        throw StateError('next() called multiple times');
      }
      index = i;

      // Check if response has been finalized by previous middleware
      if (context.finalized) {
        return context.response!;
      }

      if (i < _middlewares.length) {
        // Execute middleware
        await _middlewares[i](context, () => dispatch(i + 1));

        // After middleware completes, response should be finalized
        // (either by the middleware itself or by the handler called through next())
        if (context.finalized) {
          return context.response!;
        }

        // This shouldn't happen - either middleware or handler should finalize
        throw StateError(
          'Middleware chain completed without finalizing response',
        );
      } else {
        // All middlewares executed, now execute the final handler
        final response = await finalHandler(context);

        // Store response in context so middlewares can access it in after phase
        // Note: If handler used c.json(), c.text(), etc., response is already stored
        // But if handler directly returned Response, we need to ensure it's stored
        if (!context.finalized) {
          // Handler returned Response directly without using context methods
          context.internalFinalizeResponse(response);
        }

        return response;
      }
    }

    final response = await dispatch(0);

    // After all middlewares complete, check if any headers were added in after phase
    // If so, merge them into the final response
    if (context.responseHeaders.isNotEmpty) {
      final mergedHeaders = Map<String, String>.from(response.headers);
      mergedHeaders.addAll(context.responseHeaders);

      // Create new response with merged headers
      return Response.stream(
        response.read(),
        statusCode: response.statusCode,
        headers: mergedHeaders,
      );
    }

    return response;
  }
}
