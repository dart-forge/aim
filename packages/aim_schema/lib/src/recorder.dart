import 'package:aim_schema/src/field_spec.dart';
import 'package:aim_schema/src/reader.dart';

/// Collects what a schema asks for.
///
/// Returns dummy values, which is why a schema may not branch on what it
/// reads: there is nothing real to branch on during this pass.
final class Recorder implements Reader {
  /// The fields asked for so far, in the order they were asked for.
  final fields = <FieldSpec>[];

  @override
  String string(String name, {int? minLength, int? maxLength}) {
    fields.add(
      FieldSpec(name, 'string', minLength: minLength, maxLength: maxLength),
    );
    return '';
  }

  @override
  int integer(String name, {int? min, int? max}) {
    fields.add(FieldSpec(name, 'integer', min: min, max: max));
    return 0;
  }

  @override
  String? stringOrNull(String name, {int? minLength, int? maxLength}) {
    fields.add(
      FieldSpec(
        name,
        'string',
        required: false,
        minLength: minLength,
        maxLength: maxLength,
      ),
    );
    return null;
  }
}
