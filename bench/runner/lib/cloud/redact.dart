import 'package:bench_runner/cloud/config.dart';

/// Category labels for the identifying tokens found verbatim in [json]
/// that must never reach a committed results file: the platform domains
/// that a deployed URL lives under, and the account identifiers from
/// [config] that name a specific project. Empty when [json] is clean.
///
/// The returned strings are category labels (`'workers.dev'`, `'firebase
/// project id'`, ...), never the raw matched value: a caller that reports
/// this list — to stderr, a log, an exception message — must not end up
/// printing the very identifier this check exists to keep out of sight.
///
/// A pure string check, deliberately: it runs on the JSON that is about to
/// be written, right before the write, so a leak throws instead of landing
/// on disk.
List<String> leakedIdentifiers(String json, CloudConfig config) {
  final tokens = <String, String>{
    'workers.dev': 'workers.dev',
    'run.app': 'run.app',
    'supabase.co': 'supabase.co',
    config.firebaseProject: 'firebase project id',
    config.supabaseProjectRef: 'supabase project ref',
    config.workersNamePrefix: 'workers name prefix',
  };
  final found = <String>[];
  for (final entry in tokens.entries) {
    if (entry.key.isNotEmpty && json.contains(entry.key) && !found.contains(entry.value)) {
      found.add(entry.value);
    }
  }
  return found;
}
