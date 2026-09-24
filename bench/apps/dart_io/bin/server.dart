import 'dart:convert';
import 'dart:io';

const routeCount = 100;

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final routes = <String, String>{
    for (var i = 1; i <= routeCount; i++)
      '/r/item${i.toString().padLeft(3, '0')}': 'item${i.toString().padLeft(3, '0')}',
  };
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  server.listen((request) {
    _handle(request, routes);
  });
}

Future<void> _handle(HttpRequest request, Map<String, String> routes) async {
  final response = request.response;
  final path = request.uri.path;
  if (request.method == 'GET' && path == '/') {
    response.headers.contentType = ContentType.text;
    response.write('Hello, World!');
  } else if (request.method == 'GET' &&
      path.startsWith('/users/') &&
      !path.substring(7).contains('/')) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({
      'id': path.substring(7),
      'name': request.uri.queryParameters['name'],
    }));
  } else if (request.method == 'POST' && path == '/json') {
    final body = await utf8.decoder.bind(request).join();
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(jsonDecode(body)));
  } else if (request.method == 'GET' && routes.containsKey(path)) {
    response.headers.contentType = ContentType.text;
    response.write(routes[path]);
  } else {
    response.statusCode = HttpStatus.notFound;
  }
  await response.close();
}
