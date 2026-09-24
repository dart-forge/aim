import 'dart:io';

import 'package:yaml/yaml.dart';

/// Where to deploy and what to call the measurement origin. Read from
/// bench/cloud/config.yaml, which is git-ignored because every value in it
/// identifies an account.
class CloudConfig {
  const CloudConfig({
    required this.label,
    required this.firebaseProject,
    required this.supabaseProjectRef,
    required this.workersNamePrefix,
  });

  final String label;
  final String firebaseProject;
  final String supabaseProjectRef;
  final String workersNamePrefix;
}

CloudConfig parseCloudConfig(String yaml) {
  final doc = loadYaml(yaml);
  if (doc is! YamlMap) throw const FormatException('config is not a map');
  String require(String key) {
    final v = doc[key];
    if (v is! String || v.isEmpty) {
      throw FormatException('config.yaml has no "$key"');
    }
    return v;
  }
  return CloudConfig(
    label: require('label'),
    firebaseProject: require('firebase_project'),
    supabaseProjectRef: require('supabase_project_ref'),
    workersNamePrefix: require('workers_name_prefix'),
  );
}

Future<CloudConfig> loadCloudConfig(File file) async {
  if (!file.existsSync()) {
    throw FormatException(
      '${file.path} not found; copy config.example.yaml next to it and fill it in',
    );
  }
  return parseCloudConfig(await file.readAsString());
}
