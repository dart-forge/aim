// rask.dart — aim's task configuration. See https://github.com/dosukoi-android/rask.
import 'package:rask/rask.dart';

final config = defineConfig(tasks: [
  // build_runner in every package that consumes aim_orm_codegen (orm-sample,
  // the golden fixtures). The generator package itself is excluded.
  Task(
    'codegen',
    description: 'Run build_runner where aim_orm_codegen is used.',
    where: (pkg) => pkg.dependsOn('build_runner') && pkg.dependsOn('aim_orm_codegen'),
    run: (ctx) => ctx.dart(['run', 'build_runner', 'build', '--delete-conflicting-outputs']),
    outputs: ['lib/**.g.dart', 'test/**.g.dart'],
  ),
  // CI gate: warnings are errors.
  Task('analyze', run: (ctx) => ctx.dart(['analyze', '--fatal-warnings', ...ctx.args])),
  Task(
    'format',
    description: 'Fail when any Dart file is not formatted.',
    run: (ctx) => ctx.dart(['format', '--set-exit-if-changed', '--output=none', '.']),
  ),
]);
