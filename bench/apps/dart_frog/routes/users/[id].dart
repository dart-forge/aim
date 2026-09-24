import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context, String id) {
  return Response.json(
    body: {'id': id, 'name': context.request.uri.queryParameters['name']},
  );
}
