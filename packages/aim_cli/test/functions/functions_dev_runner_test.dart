import 'package:aim_cli/src/functions/functions_dev_runner.dart';
import 'package:test/test.dart';

void main() {
  group('demoProjectId', () {
    test('prefixes the package name with demo-', () {
      expect(demoProjectId('my_app'), 'demo-my-app');
    });

    test('drops characters a Firebase project id cannot hold', () {
      expect(demoProjectId('My_App.2'), 'demo-my-app-2');
    });

    test('falls back when there is no package name', () {
      expect(demoProjectId(null), 'demo-aim');
      expect(demoProjectId(''), 'demo-aim');
    });

    test('stays within the 30 characters a project id allows', () {
      final id = demoProjectId('a_very_long_package_name_that_keeps_going');
      expect(id.length, lessThanOrEqualTo(30));
      expect(id, startsWith('demo-'));
      expect(id, isNot(endsWith('-')));
    });
  });

  group('emulatorProjectId', () {
    test('is null when .firebaserc already names a project', () {
      expect(
        emulatorProjectId(hasFirebaserc: true, packageName: 'my_app'),
        isNull,
      );
    });

    test('falls back to demoProjectId when there is no .firebaserc', () {
      expect(
        emulatorProjectId(hasFirebaserc: false, packageName: 'my_app'),
        'demo-my-app',
      );
    });
  });
}
