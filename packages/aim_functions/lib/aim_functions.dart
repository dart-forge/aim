/// Cloud Functions for Firebase adapter for the Aim framework.
///
/// Runs an [Aim] application as a Cloud Functions `onRequest` HTTP function.
/// See [AimFunctions.serveFunction] for usage.
library;

export 'package:aim_core/aim_core.dart';

export 'src/functions_request.dart' show ShelfRequestAccess;
export 'src/serve_functions.dart' show AimFunctions;
