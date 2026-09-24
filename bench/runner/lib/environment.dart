import 'dart:io';

import 'package:yaml/yaml.dart';

/// Resolved versions of [packages] from a pubspec.lock's contents.
Map<String, String> lockedVersions(String lockYaml, List<String> packages) {
  final doc = loadYaml(lockYaml) as YamlMap;
  final entries = doc['packages'] as YamlMap? ?? YamlMap();
  return {
    for (final name in packages)
      name: switch (entries[name]) {
        null => 'absent',
        final YamlMap e when e['source'] == 'path' => '${e['version']} (path)',
        final YamlMap e => '${e['version']}',
        _ => 'unknown',
      },
  };
}

Future<String> _run(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  final out = (result.stdout as String).trim();
  return out.isNotEmpty ? out : (result.stderr as String).trim();
}

/// Hardware, OS and toolchain the numbers were produced on (macOS).
Future<Map<String, Object?>> captureEnvironment() async {
  return {
    'os': 'macOS ${await _run('sw_vers', ['-productVersion'])}',
    'arch': await _run('uname', ['-m']),
    'cpu': await _run('sysctl', ['-n', 'machdep.cpu.brand_string']),
    'cores': int.tryParse(await _run('sysctl', ['-n', 'hw.ncpu'])),
    'memoryBytes': int.tryParse(await _run('sysctl', ['-n', 'hw.memsize'])),
    'dart': await _run('dart', ['--version']),
    'hostname': await _run('hostname', ['-s']),
  };
}

/// Short commit hash of [repo]'s HEAD.
Future<String> gitShortHead(Directory repo) async {
  final result = await Process.run(
    'git',
    ['rev-parse', '--short', 'HEAD'],
    workingDirectory: repo.path,
  );
  return (result.stdout as String).trim();
}
