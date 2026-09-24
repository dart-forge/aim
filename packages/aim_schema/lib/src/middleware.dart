import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/src/errors.dart';

/// Answers 400 with the list of errors when a schema rejects the input.
///
/// Only [ValidationException] is handled here; every other error still
/// propagates to the application's own [Aim.onError] handler (or the
/// default 500) exactly as it would without this middleware.
///
/// The response body is:
/// ```json
/// {"error": "Bad Request", "details": [{"path": "name", "message": "..."}]}
/// ```
Middleware<E> validationErrorsAsBadRequest<E extends Variables>() {
  return (Context<E> c, Next next) async {
    try {
      await next();
    } on ValidationException catch (e) {
      c.json({
        'error': 'Bad Request',
        'details': [
          for (final error in e.errors)
            {'path': error.path, 'message': error.message},
        ],
      }, statusCode: 400);
    }
  };
}
