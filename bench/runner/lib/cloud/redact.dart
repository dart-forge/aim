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

/// A skip reason as it will be shown and recorded: every occurrence of
/// [base]'s origin and its bare host replaced with [targetName], and the
/// result truncated to 300 characters.
///
/// A skip reason can come from a response body (a mismatch) or from any
/// [StateError] a target's build, deploy or measurement raised, and either
/// can carry the deployed host — a platform's own error page tends to
/// repeat it. This runs right before that reason is recorded, so it is
/// scrubbed once, the same way, regardless of where it came from.
String scrubReason(String reason, Uri base, String targetName) {
  final scrubbed = reason
      .replaceAll(base.toString(), targetName)
      .replaceAll(base.host, targetName);
  return scrubbed.length > 300 ? scrubbed.substring(0, 300) : scrubbed;
}
