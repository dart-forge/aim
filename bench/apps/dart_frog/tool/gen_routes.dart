import 'dart:io';

const routeCount = 100;

/// Writes routes/r/item1.dart .. item<routeCount>.dart. Run from the app
/// directory: `dart run tool/gen_routes.dart`.
void main() {
  final dir = Directory('routes/r');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  for (var i = 1; i <= routeCount; i++) {
    File('${dir.path}/item$i.dart').writeAsStringSync('''
import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) => Response(body: 'item$i');
''');
  }
}
