import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_postgres/src/types/pg_type_decoder.dart';

/// Thrown when a cell of a known PostgreSQL type cannot be converted to its
/// Dart representation (for example `'infinity'::timestamp`, malformed
/// JSON, or bytea in the legacy escape format).
///
/// The whole query fails; the connection itself stays healthy because
/// decoding happens after ReadyForQuery has been read (A-046).
class PostgresDecodeException implements Exception {
  PostgresDecodeException({
    required this.columnName,
    required this.typeOid,
    required this.rawValue,
    required this.cause,
  });

  /// Name of the column whose value failed to decode.
  final String columnName;

  /// PostgreSQL type OID of the column.
  final int typeOid;

  /// Text as received from the server.
  final String rawValue;

  /// The underlying error, usually a [FormatException].
  final Object cause;

  @override
  String toString() =>
      'PostgresDecodeException: column "$columnName" (type oid $typeOid): '
      'cannot decode "$rawValue": $cause';
}

/// Resolves one decoder per result column. Resolved once per result set so
/// the per-cell work is a single function call, not a map lookup.
///
/// `null` means "leave the cell as is": either the type is unknown (text is
/// kept as [String]) or the column is in binary format (bytes are kept as
/// [Uint8List]; this driver never requests binary, so it is defensive).
List<PgDecoder?> resolveColumnDecoders(List<Map<String, dynamic>> columns) {
  return [
    for (final c in columns)
      (c['formatCode'] as int) != 0
          ? null
          : PgTypeDecoder.forOid(c['typeOid'] as int),
  ];
}

/// Decodes raw DataRow cells into Dart values using [columns]' types.
///
/// Text-format cells are UTF-8 decoded and then converted by the column's
/// decoder (unknown types stay [String]). Binary-format cells are passed
/// through as [Uint8List]. NULL cells stay `null`.
///
/// A row whose cell count does not match [columns] is a protocol-shape
/// surprise, not a normal decode failure, but it is still reported as a
/// [PostgresDecodeException] so it never surfaces as a bare [RangeError].
List<List<Object?>> decodeRows(
  List<Map<String, dynamic>> columns,
  List<List<Uint8List?>> rawRows,
) {
  final decoders = resolveColumnDecoders(columns);
  return [
    for (final raw in rawRows)
      [
        for (var i = 0; i < _checkedLength(raw, columns); i++)
          _decodeCell(columns[i], decoders[i], raw[i]),
      ],
  ];
}

int _checkedLength(List<Uint8List?> raw, List<Map<String, dynamic>> columns) {
  if (raw.length != columns.length) {
    throw PostgresDecodeException(
      columnName: '<row>',
      typeOid: 0,
      rawValue: 'DataRow has ${raw.length} cells for ${columns.length} columns',
      cause: StateError('cell/column count mismatch'),
    );
  }
  return raw.length;
}

Object? _decodeCell(
  Map<String, dynamic> column,
  PgDecoder? decoder,
  Uint8List? bytes,
) {
  if (bytes == null) return null;
  if ((column['formatCode'] as int) != 0) return bytes;
  final text = utf8.decode(bytes);
  if (decoder == null) return text;
  try {
    return decoder(text);
  } catch (e) {
    throw PostgresDecodeException(
      columnName: column['name'] as String,
      typeOid: column['typeOid'] as int,
      rawValue: text,
      cause: e,
    );
  }
}
