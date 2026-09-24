import 'dart:io';

const routeCount = 100;

/// Writes routes/r/item001.dart .. item100.dart, zero-padded to 3 digits so
/// dart_frog's file-name-order route registration matches every other
/// app's registration order (see bench/README.md for why that matters).
/// Run from the app directory: `dart run tool/gen_routes.dart`.
void main() {
  final dir = Directory('routes/r');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  for (var i = 1; i <= routeCount; i++) {
    final name = 'item${i.toString().padLeft(3, '0')}';
    File('${dir.path}/$name.dart').writeAsStringSync('''
import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) => Response(body: '$name');
''');
  }
}
