/// Validate request data and read it back with static types.
library;

export 'src/context.dart' show SchemaContext;
export 'src/errors.dart' show ValidationError, ValidationException;
export 'src/field_spec.dart' show FieldSpec;
export 'src/middleware.dart' show validationErrorsAsBadRequest;
export 'src/reader.dart' show Reader;
export 'src/schema.dart' show Schema;
