import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run release:create_release <version>');
    stderr.writeln('Example: dart run release:create_release 0.1.0');
    exit(1);
  }

  final version = args[0];
  final dryRun = args.contains('--dry-run');

  final changelogFile = File('CHANGELOG.md');
  if (!changelogFile.existsSync()) {
    stderr.writeln('CHANGELOG.md not found. Run from repository root.');
    exit(1);
  }

  // Extract release notes for the specified version
  final content = changelogFile.readAsStringSync();
  final releaseNotes = _extractVersionNotes(content, version);

  if (releaseNotes == null) {
    stderr.writeln('Version $version not found in CHANGELOG.md');
    exit(1);
  }

  stdout.writeln('Creating GitHub release for $version\n');
  stdout.writeln('Release notes:');
  stdout.writeln('-' * 40);
  stdout.writeln(releaseNotes);
  stdout.writeln('-' * 40);
  stdout.writeln('');

  if (dryRun) {
    stdout.writeln('Dry run mode - not creating release.');
    stdout.writeln('Run without --dry-run to create the release.');
    return;
  }

  // Check if gh is available
  final whichResult = await Process.run('which', ['gh']);
  if (whichResult.exitCode != 0) {
    stderr.writeln('GitHub CLI (gh) not found. Install it first:');
    stderr.writeln('  brew install gh');
    exit(1);
  }

  // Create the release
  final result = await Process.run(
    'gh',
    [
      'release',
      'create',
      version,
      '--title',
      version,
      '--notes',
      releaseNotes,
    ],
    runInShell: true,
  );

  stdout.write(result.stdout);
  if (result.stderr.toString().isNotEmpty) {
    stderr.write(result.stderr);
  }

  if (result.exitCode != 0) {
    stderr.writeln('Failed to create release');
    exit(1);
  }

  stdout.writeln('Release created successfully!');
  stdout.writeln('https://github.com/dart-forge/aim/releases/tag/$version');
}

String? _extractVersionNotes(String content, String version) {
  final lines = content.split('\n');
  final startPattern = RegExp('^## $version\$');
  final endPattern = RegExp('^## ');

  int? startIndex;
  int? endIndex;

  for (var i = 0; i < lines.length; i++) {
    if (startIndex == null && startPattern.hasMatch(lines[i])) {
      startIndex = i + 1; // Skip the version header line
    } else if (startIndex != null && endPattern.hasMatch(lines[i])) {
      endIndex = i;
      break;
    }
  }

  if (startIndex == null) return null;

  endIndex ??= lines.length;

  final notes = lines.sublist(startIndex, endIndex).join('\n').trim();
  return notes.isEmpty ? 'No release notes.' : notes;
}
