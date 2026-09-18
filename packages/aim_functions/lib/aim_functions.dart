/// Cloud Functions for Firebase adapter for the Aim framework.
///
/// This is Task 1 of the adapter: the shelf ↔ aim translation that Cloud
/// Functions' `onRequest` handler will be built on in a later task.
library;

export 'package:aim_core/aim_core.dart';

export 'src/functions_request.dart' show toAimRequest;
export 'src/functions_response.dart' show toShelfResponse;
