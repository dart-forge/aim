import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:aim_cli/aim_cli.dart';
import 'package:aim_cli/src/version.dart';

void main(List<String> arguments) async {
  final runner = CommandRunner('aim', 'Command-line tool for Aim framework')
    ..addCommand(CreateCommand())
    ..addCommand(DevCommand())
    ..addCommand(BuildCommand())
    ..addCommand(DbGenerateCommand())
    ..addCommand(DbMigrateCommand())
    ..addCommand(DbRollbackCommand())
    ..addCommand(DbStatusCommand())
    ..addCommand(DbResetCommand());

  runner.argParser.addFlag(
    'version',
    negatable: false,
    help: 'Print the aim_cli version.',
  );

  try {
    final results = runner.parse(arguments);
    if (results['version'] as bool) {
      print('aim_cli $aimCliVersion');
      return;
    }
    await runner.runCommand(results);
  } on UsageException catch (e) {
    print(e);
    exit(64);
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}
