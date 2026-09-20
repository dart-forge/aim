import 'dart:io';

import 'package:aim_cli/src/config/aim_config.dart';
import 'package:test/test.dart';

void main() {
  group('AimConfig.parse', () {
    test('defaults to the server target when aim: is absent', () {
      final config = AimConfig.parse('name: app\n');
      expect(config.target, AimTarget.server);
      expect(config.configuredEntry, isNull);
      expect(config.defaultEntry, 'bin/server.dart');
      expect(config.env, isEmpty);
    });

    test('reads target: edge and switches the default entry', () {
      final config = AimConfig.parse('aim:\n  target: edge\n');
      expect(config.target, AimTarget.edge);
      expect(config.defaultEntry, 'lib/main.dart');
    });

    test('rejects an unknown target', () {
      expect(
        () => AimConfig.parse('aim:\n  target: deno\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'resolveEntry prefers the CLI override, then aim.entry, then default',
      () {
        final withEntry = AimConfig.parse('aim:\n  entry: bin/api.dart\n');
        expect(withEntry.resolveEntry('bin/cli.dart'), 'bin/cli.dart');
        expect(withEntry.resolveEntry(null), 'bin/api.dart');

        final withoutEntry = AimConfig.parse('aim:\n  target: edge\n');
        expect(withoutEntry.resolveEntry(null), 'lib/main.dart');
      },
    );

    test('expands env values', () {
      final config = AimConfig.parse(
        'aim:\n  env:\n    PORT: "8080"\n    HOST: \${AIM_TEST_UNSET_HOST:0.0.0.0}\n',
      );
      expect(config.env, {'PORT': '8080', 'HOST': '0.0.0.0'});
    });

    test('ignores a non-map aim: section', () {
      final config = AimConfig.parse('aim: true\n');
      expect(config.target, AimTarget.server);
      expect(config.env, isEmpty);
    });
  });

  group('AimConfig.parse database', () {
    test('expands a default in aim.database.url', () {
      final config = AimConfig.parse(
        'aim:\n  database:\n'
        '    url: \${AIM_TEST_UNSET_DB:postgresql://localhost:5432/dev}\n',
      );
      expect(config.database.url, 'postgresql://localhost:5432/dev');
    });

    test('treats an unset url with no default as absent', () {
      final config = AimConfig.parse(
        'aim:\n  database:\n    url: \${AIM_TEST_UNSET_DB}\n',
      );
      expect(config.database.url, isNull);
    });

    test('expands a default in aim.database.schema', () {
      final config = AimConfig.parse(
        'aim:\n  database:\n'
        '    schema: \${AIM_TEST_UNSET_SCHEMA:lib/db/schema.dart}\n',
      );
      expect(config.database.configuredSchema, 'lib/db/schema.dart');
    });

    test('resolveSchema prefers --path, then the configured path', () {
      final configured = AimConfig.parse(
        'aim:\n  database:\n    schema: lib/db/schema.dart\n',
      );
      expect(
        configured.database.resolveSchema('lib/other.dart'),
        'lib/other.dart',
      );
      expect(configured.database.resolveSchema(null), 'lib/db/schema.dart');

      final none = AimConfig.parse('name: app\n');
      expect(none.database.resolveSchema(null), 'lib/schema');
    });

    test('has no database settings when aim.database is absent', () {
      final config = AimConfig.parse('aim:\n  entry: bin/server.dart\n');
      expect(config.database.url, isNull);
      expect(config.database.configuredSchema, isNull);
    });

    test('ignores a non-map aim.database section', () {
      final config = AimConfig.parse('aim:\n  database: true\n');
      expect(config.database.url, isNull);
      expect(config.database.configuredSchema, isNull);
    });
  });

  group('functions target', () {
    test('parses target: functions', () {
      final config = AimConfig.parse('''
name: my_app
aim:
  target: functions
''');
      expect(config.target, AimTarget.functions);
      expect(config.defaultEntry, 'bin/server.dart');
      expect(config.packageName, 'my_app');
    });

    test('an unknown target names all three in the message', () {
      expect(
        () => AimConfig.parse('aim:\n  target: lambda\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('server'), contains('edge'), contains('functions')),
          ),
        ),
      );
    });

    test('packageName is null when pubspec has no name', () {
      expect(AimConfig.parse('aim:\n  target: server\n').packageName, isNull);
    });
  });

  group('AimConfig.loadOrDefault', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('aim_config_');
    });

    tearDown(() async => tmp.delete(recursive: true));

    test('reads the database section from the file', () async {
      final pubspec = File('${tmp.path}/pubspec.yaml');
      await pubspec.writeAsString(
        'name: app\naim:\n  database:\n'
        '    url: postgresql://localhost/app\n',
      );
      final config = await AimConfig.loadOrDefault(pubspec.path);
      expect(config.database.url, 'postgresql://localhost/app');
    });

    test('returns defaults when the file is absent', () async {
      final config = await AimConfig.loadOrDefault('${tmp.path}/pubspec.yaml');
      expect(config.database.url, isNull);
      expect(config.target, AimTarget.server);
    });
  });
}
