import 'package:aim_schema/aim_schema.dart';

final badOut = Output<({int id})>((w) => [w.string('id', (v) => v.id)]);
