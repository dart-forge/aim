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

class ColdProbe {
  const ColdProbe({required this.ttfb, required this.notFoundRetries});
  final Duration ttfb;
  final int notFoundRetries;
}

/// First request to a freshly deployed target over a new connection. A 404
/// is retried (the platform's edge answers 404 while a brand-new route is
/// still propagating; that answer never reaches the app, so it does not warm
/// it). The first non-404 response's TTFB is the cold sample.
Future<ColdProbe> coldProbe(
  Uri url, {
  Duration timeout = const Duration(seconds: 60),
  Duration interval = const Duration(seconds: 1),
}) async {
  final watch = Stopwatch()..start();
  var retries = 0;
  while (true) {
    final http = HttpClient();
    try {
      final requestWatch = Stopwatch()..start();
      final request = await http.openUrl('GET', url);
      final response = await request.close();
      final elapsed = requestWatch.elapsed;
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == 200) {
        return ColdProbe(ttfb: elapsed, notFoundRetries: retries);
      }
      if (response.statusCode != 404) {
        throw StateError('GET $url answered ${response.statusCode}: $body');
      }
      if (watch.elapsed >= timeout) {
        throw StateError('GET $url kept answering 404 after ${watch.elapsed}: $body');
      }
      retries++;
      await Future<void>.delayed(interval);
    } finally {
      http.close(force: true);
    }
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
