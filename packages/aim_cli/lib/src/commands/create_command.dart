import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;
import 'package:aim_cli/src/utils/validators.dart';
import 'package:aim_cli/src/utils/file_generator.dart';
import 'package:aim_cli/src/templates/templates.dart';

class CreateCommand extends Command {
  @override
  final name = 'create';

  @override
  final description = 'Create a new Aim framework project';

  @override
  String get invocation => 'aim create <project_name>';

  CreateCommand() {
    argParser.addOption(
      'target',
      allowed: ['server', 'edge', 'functions'],
      defaultsTo: 'server',
      help:
          'Runtime target: server (dart:io), edge (Cloudflare workerd) or '
          'functions (Cloud Functions for Firebase)',
    );
    argParser.addOption(
      'firebase-project',
      help:
          'Firebase project id written to .firebaserc (target: functions). '
          'Pass an empty value to skip .firebaserc and bind the project later '
          'with `firebase use --add`.',
    );
  }

  @override
  Future<void> run() async {
    // Get project name
    if (argResults?.rest.isEmpty ?? true) {
      throw UsageException('Please specify a project name', invocation);
    }

    final projectName = argResults!.rest.first;
    final target = argResults!['target'] as String;

    // Validation
    if (!ProjectNameValidator.isValid(projectName)) {
      throw UsageException(
        ProjectNameValidator.getErrorMessage(projectName),
        invocation,
      );
    }

    // Create project directory
    final projectDir = Directory(projectName);

    if (await projectDir.exists()) {
      throw UsageException(
        'Directory "$projectName" already exists',
        invocation,
      );
    }

    print('📦 Creating project "$projectName"...');

    final firebaseProject = target == 'functions'
        ? _resolveFirebaseProject()
        : '';

    try {
      // Create directory structure
      await _createProjectStructure(projectName, target, firebaseProject);

      print('');
      print('✅ Project created successfully!');
      print('');
      print('Next steps:');
      print('  cd $projectName');
      print('  dart pub get');
      print('  aim dev');
      if (target == 'edge') {
        print('  # requires Node: npx wrangler@4 is downloaded on first run');
      }
      if (target == 'functions') {
        print('  # requires the Firebase CLI:');
        print('  #   npm install -g firebase-tools');
        print('  #   firebase login');
        print('  #   firebase experiments:enable dartfunctions');
        if (firebaseProject.isEmpty) {
          print('  # then bind a Firebase project: firebase use --add');
        }
      }
      print('');
    } catch (e) {
      throw Exception('Failed to create project: $e');
    }
  }

  /// The Firebase project id for `.firebaserc`, or an empty string when there
  /// is none to write.
  ///
  /// Nothing else can supply this value: a project id guessed from the
  /// directory name would name a project that does not exist, and a
  /// `.firebaserc` pointing at one is worse than none at all. Without a
  /// terminal to ask, the file is left out.
  String _resolveFirebaseProject() {
    final fromFlag = argResults?['firebase-project'] as String?;
    if (fromFlag != null) return fromFlag.trim();
    if (!stdin.hasTerminal) return '';
    stdout.write('Firebase project id (leave empty to set it up later): ');
    return stdin.readLineSync()?.trim() ?? '';
  }

  Future<void> _createProjectStructure(
    String projectName,
    String target,
    String firebaseProject,
  ) async {
    final workerName = projectName.replaceAll('_', '-');
    final variables = {
      'projectName': projectName,
      'workerName': workerName,
      'firebaseProject': firebaseProject,
    };

    // Get templates from string constants and generate
    final templates = switch (target) {
      'edge' => {
        'pubspec.yaml': Templates.edgePubspec,
        'README.md': Templates.edgeReadme,
        'lib/main.dart': Templates.edgeMain,
        'src/index.mjs': Templates.edgeIndexMjs,
        'wrangler.jsonc': Templates.edgeWranglerJsonc,
        '.gitignore': Templates.edgeGitignore,
      },
      'functions' => {
        'pubspec.yaml': Templates.functionsPubspec,
        'README.md': Templates.functionsReadme,
        'bin/server.dart': Templates.functionsServer,
        'lib/src/server.dart': Templates.functionsApp,
        'test/${projectName}_test.dart': Templates.testTest,
        '.gitignore': Templates.functionsGitignore,
        'firebase.json': Templates.functionsFirebaseJson,
        if (firebaseProject.isNotEmpty)
          '.firebaserc': Templates.functionsFirebaserc,
      },
      _ => {
        'pubspec.yaml': Templates.projectPubspec,
        'README.md': Templates.projectReadme,
        'bin/server.dart': Templates.binServer,
        'lib/src/server.dart': Templates.libSrcServer,
        'test/${projectName}_test.dart': Templates.testTest,
        '.gitignore': Templates.gitignore,
        'Dockerfile': Templates.dockerfile,
        '.dockerignore': Templates.dockerignore,
      },
    };

    for (final entry in templates.entries) {
      final filePath = path.join(projectName, entry.key);
      final template = entry.value;

      print('  Creating: $filePath');

      final content = FileGenerator.replaceVariables(template, variables);
      await FileGenerator.writeFile(filePath, content);
    }
  }
}
