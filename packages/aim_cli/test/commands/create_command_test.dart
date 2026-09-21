import 'dart:io';

import 'package:aim_cli/aim_cli.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String previousCwd;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aim_create_');
    previousCwd = Directory.current.path;
    Directory.current = tmp;
  });

  tearDown(() async {
    Directory.current = previousCwd;
    await tmp.delete(recursive: true);
  });

  Future<void> create(List<String> args) {
    final runner = CommandRunner<void>('aim', 'test')
      ..addCommand(CreateCommand());
    return runner.run(['create', ...args]);
  }

  String read(String relative) =>
      File(p.join(tmp.path, relative)).readAsStringSync();

  test('scaffolds a workers project', () async {
    await create(['my_edge', '--target', 'workers']);

    final files = Directory(p.join(tmp.path, 'my_edge'))
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => p.relative(f.path, from: p.join(tmp.path, 'my_edge')))
        .toSet();
    expect(files, {
      'pubspec.yaml',
      'README.md',
      'lib/main.dart',
      'src/index.mjs',
      'wrangler.jsonc',
      '.gitignore',
    });

    expect(read('my_edge/pubspec.yaml'), contains('target: workers'));
    expect(read('my_edge/pubspec.yaml'), contains('aim_workers:'));
    expect(read('my_edge/pubspec.yaml'), contains('name: my_edge'));
    expect(read('my_edge/lib/main.dart'), contains('app.serveWorkers();'));
    expect(read('my_edge/wrangler.jsonc'), contains('"name": "my-edge"'));
    expect(read('my_edge/wrangler.jsonc'), contains('"main": "src/index.mjs"'));
    expect(read('my_edge/src/index.mjs'), contains('build/workers/main.wasm'));
  });

  test('scaffolds a supabase project', () async {
    await create(['my_api', '--target', 'supabase']);

    final files = Directory(p.join(tmp.path, 'my_api'))
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => p.relative(f.path, from: p.join(tmp.path, 'my_api')))
        .toSet();
    expect(files, {
      'pubspec.yaml',
      'README.md',
      'lib/main.dart',
      'supabase/functions/my_api/index.ts',
      'supabase/config.toml',
      '.gitignore',
    });

    expect(read('my_api/pubspec.yaml'), contains('target: supabase'));
    expect(read('my_api/pubspec.yaml'), contains('aim_deno:'));
    expect(read('my_api/pubspec.yaml'), contains('name: my_api'));
    expect(
      read('my_api/lib/main.dart'),
      contains("app.serveDeno(basePath: 'my_api');"),
    );
    expect(read('my_api/supabase/config.toml'), contains('[functions.my_api]'));
    expect(
      read('my_api/supabase/config.toml'),
      contains('./functions/my_api/main.wasm'),
    );
    expect(
      read('my_api/supabase/functions/my_api/index.ts'),
      contains('__aimFetch'),
    );
  });

  test('scaffolds a server project by default', () async {
    await create(['my_server']);

    expect(
      File(p.join(tmp.path, 'my_server/bin/server.dart')).existsSync(),
      isTrue,
    );
    expect(File(p.join(tmp.path, 'my_server/Dockerfile')).existsSync(), isTrue);
    expect(
      read('my_server/pubspec.yaml'),
      matches(RegExp(r'aim_server: \^\d+\.\d+\.\d+')),
    );
    expect(read('my_server/pubspec.yaml'), isNot(contains('target: workers')));
  });

  test('rejects an unknown target', () async {
    expect(create(['x', '--target', 'deno']), throwsA(isA<UsageException>()));
  });

  test('scaffolds a functions project', () async {
    await create([
      'my_fn',
      '--target',
      'functions',
      '--firebase-project',
      'my-real-project',
    ]);

    final files = Directory(p.join(tmp.path, 'my_fn'))
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => p.relative(f.path, from: p.join(tmp.path, 'my_fn')))
        .toSet();
    expect(files, {
      'pubspec.yaml',
      'README.md',
      'bin/server.dart',
      'lib/src/server.dart',
      'test/my_fn_test.dart',
      '.gitignore',
      'firebase.json',
      '.firebaserc',
    });

    expect(read('my_fn/pubspec.yaml'), contains('target: functions'));
    expect(read('my_fn/pubspec.yaml'), contains('aim_functions:'));
    expect(read('my_fn/pubspec.yaml'), contains('firebase_functions: ^0.8.0'));
    expect(read('my_fn/pubspec.yaml'), contains('build_runner:'));
    expect(read('my_fn/pubspec.yaml'), contains('name: my_fn'));

    // The Dart package and firebase.json sit side by side, so `aim dev` and
    // the emulator agree on where the project root is.
    expect(read('my_fn/firebase.json'), contains('"source": "."'));
    expect(read('my_fn/firebase.json'), contains('"runtime": "dart3"'));

    // build/ must stay in the deploy package: the functions.yaml that
    // build_runner generates points its command at
    // ./build/cli/linux_x64/bundle/bin/server, which is the artifact the
    // Firebase CLI uploads.
    expect(read('my_fn/firebase.json'), isNot(contains('"build"')));
    expect(read('my_fn/.firebaserc'), contains('"my-real-project"'));

    expect(read('my_fn/bin/server.dart'), contains('serveFunction()'));
    expect(
      read('my_fn/bin/server.dart'),
      contains("import 'package:my_fn/src/server.dart';"),
    );
    expect(read('my_fn/lib/src/server.dart'), contains('Aim createApp()'));
  });

  test('an empty firebase project id leaves .firebaserc out', () async {
    await create(['my_fn', '--target', 'functions', '--firebase-project', '']);

    expect(
      File(p.join(tmp.path, 'my_fn', '.firebaserc')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(tmp.path, 'my_fn', 'firebase.json')).existsSync(),
      isTrue,
    );
  });

  test('rejects a --firebase-project with spaces', () async {
    // Firebase would reject it much later, naming neither the flag nor the
    // file it was written to.
    await expectLater(
      create([
        'my_fn',
        '--target',
        'functions',
        '--firebase-project',
        'My Project',
      ]),
      throwsA(isA<UsageException>()),
    );
    expect(Directory(p.join(tmp.path, 'my_fn')).existsSync(), isFalse);
  });

  test('rejects a --firebase-project containing a quote', () async {
    // Interpolated as-is, this would produce malformed JSON in .firebaserc.
    await expectLater(
      create(['my_fn', '--target', 'functions', '--firebase-project', 'a"b']),
      throwsA(isA<UsageException>()),
    );
    expect(Directory(p.join(tmp.path, 'my_fn')).existsSync(), isFalse);
  });
}
