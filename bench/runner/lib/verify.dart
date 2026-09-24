import 'dart:convert';
import 'dart:io';

import 'package:bench_runner/cloud/urls.dart';
import 'package:bench_runner/scenarios.dart';
import 'package:collection/collection.dart';

/// One scenario an app answered differently from the shared definition.
class Mismatch {
  const Mismatch(this.scenarioId, this.message);

  final String scenarioId;
  final String message;

  @override
  String toString() => '$scenarioId: $message';
}

const _deepEquals = DeepCollectionEquality();

/// Sends every scenario to the app at [base] and compares status and body.
///
/// Headers are not compared: frameworks differ in their defaults and this
/// benchmark keeps those defaults. Returns an empty list when all match.
Future<List<Mismatch>> verifyApp(Uri base, {HttpClient? client}) async {
  final http = client ?? HttpClient();
  final mismatches = <Mismatch>[];
  try {
    for (final scenario in scenarios) {
      final request = await http.openUrl(
        scenario.method,
        joinPath(base, scenario.path),
      );
      if (scenario.requestBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(scenario.requestBody);
      }
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        mismatches.add(Mismatch(
          scenario.id,
          'expected status 200, got ${response.statusCode}',
        ));
        continue;
      }
      final matches = switch (scenario.kind) {
        BodyKind.text => body == scenario.expected,
        BodyKind.json => _jsonMatches(body, scenario.expected),
      };
      if (!matches) {
        mismatches.add(Mismatch(
          scenario.id,
          'expected body ${_describe(scenario.expected)}, got $body',
        ));
      }
    }
  } finally {
    if (client == null) http.close(force: true);
  }
  return mismatches;
}

bool _jsonMatches(String body, Object expected) {
  try {
    return _deepEquals.equals(jsonDecode(body), expected);
  } on FormatException {
    return false;
  }
}

String _describe(Object expected) =>
    expected is String ? expected : jsonEncode(expected);
