import 'dart:convert';
import 'dart:io';

/// Time from opening the request to receiving the response headers. With no
/// [client] a fresh one is used and closed afterwards, so the number includes
/// a new TCP connection and TLS handshake — what a cold request pays.
Future<Duration> timeToFirstByte(
  Uri url, {
  String method = 'GET',
  String? jsonBody,
  HttpClient? client,
}) async {
  final http = client ?? HttpClient();
  final watch = Stopwatch()..start();
  try {
    final request = await http.openUrl(method, url);
    if (jsonBody != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonBody);
    }
    final response = await request.close();
    final elapsed = watch.elapsed;
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw StateError('$method $url answered ${response.statusCode}: $body');
    }
    return elapsed;
  } finally {
    if (client == null) http.close(force: true);
  }
}

/// [count] requests one after another on a kept-alive [client].
Future<List<Duration>> sequentialLatencies(
  Uri url,
  int count, {
  String method = 'GET',
  String? jsonBody,
  required HttpClient client,
}) async {
  final out = <Duration>[];
  for (var i = 0; i < count; i++) {
    out.add(await timeToFirstByte(url, method: method, jsonBody: jsonBody, client: client));
  }
  return out;
}
