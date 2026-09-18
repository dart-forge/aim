import 'package:aim_functions/aim_functions.dart';
import 'package:firebase_functions/firebase_functions.dart';

void main(List<String> args) {
  final app = Aim()
    ..get('/', (c) async => c.text('Hello from Aim on Cloud Functions!'))
    ..get('/users/:id', (c) async => c.json({'id': c.param('id')}));

  runFunctions((firebase) {
    firebase.https.onRequest(name: 'api', app.serveFunction());
  });
}
