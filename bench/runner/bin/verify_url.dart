import 'dart:io';

import 'package:bench_runner/verify.dart';

/// Runs [verifyApp] against a URL given on the command line and prints any
/// mismatches. Exits 1 if any scenario mismatched, 0 otherwise.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run bin/verify_url.dart <url>');
    exitCode = 64;
    return;
  }
  final base = Uri.parse(args.single);
  final mismatches = await verifyApp(base);
  if (mismatches.isEmpty) {
    stdout.writeln('All scenarios matched.');
    exitCode = 0;
    return;
  }
  for (final mismatch in mismatches) {
    stdout.writeln(mismatch);
  }
  exitCode = 1;
}
