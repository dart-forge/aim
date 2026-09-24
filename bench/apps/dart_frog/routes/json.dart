import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  final body = await context.request.json();
  return Response.json(body: body);
}
