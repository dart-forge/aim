import 'package:bench_runner/cloud/config.dart';

/// Identifying tokens found verbatim in [json] that must never reach a
/// committed results file: the platform domains that a deployed URL lives
/// under, and the account identifiers from [config] that name a specific
/// project. Empty when [json] is clean.
///
/// A pure string check, deliberately: it runs on the JSON that is about to
/// be written, right before the write, so a leak throws instead of landing
/// on disk.
List<String> leakedIdentifiers(String json, CloudConfig config) {
  final tokens = <String>[
    'workers.dev',
    'run.app',
    'supabase.co',
    config.firebaseProject,
    config.supabaseProjectRef,
    config.workersNamePrefix,
  ];
  final found = <String>[];
  for (final token in tokens) {
    if (token.isNotEmpty && json.contains(token) && !found.contains(token)) {
      found.add(token);
    }
  }
  return found;
}
