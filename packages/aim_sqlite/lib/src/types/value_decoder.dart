import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_sqlite/src/sqlite_exception.dart';
import 'package:aim_sqlite/src/types/decl_type.dart';
import 'package:aim_sqlite/src/types/raw_value.dart';

/// Julian day number of 1970-01-01T00:00:00Z.
const _unixEpochJulianDay = 2440587.5;
const _millisecondsPerDay = 86400000;

/// As far from the epoch as a [DateTime] reaches: 100,000,000 days either
/// side of it. Anything past this is not an instant, however it was stored.
const _maxMillisecondsSinceEpoch = 8640000000000000;
const _maxSecondsSinceEpoch = _maxMillisecondsSinceEpoch ~/ 1000;

/// Turns one stored value into the Dart type [kind] promises.
///
/// [column] and [declType] are only used to describe a failure.
Object? decodeValue({
  required SqliteColumnKind kind,
  required SqliteRawValue raw,
  required String column,
  required String? declType,
}) {
  if (raw is SqliteRawNull) return null;

  Never fail(String message) => throw SqliteDecodeException(
    column: column,
    declType: declType,
    rawValue: raw.value,
    message: message,
  );

  switch (kind) {
    case SqliteColumnKind.raw:
      return raw.value;

    case SqliteColumnKind.integer:
      return switch (raw) {
        SqliteRawInteger(:final value) => value,
        SqliteRawReal(:final value) => value.toInt(),
        SqliteRawText(:final value) =>
          int.tryParse(value) ?? fail('not an integer'),
        SqliteRawBlob() => fail('an integer column holds a blob'),
        SqliteRawNull() => null,
      };

    case SqliteColumnKind.real:
      return switch (raw) {
        SqliteRawReal(:final value) => value,
        SqliteRawInteger(:final value) => value.toDouble(),
        SqliteRawText(:final value) =>
          double.tryParse(value) ?? fail('not a number'),
        SqliteRawBlob() => fail('a real column holds a blob'),
        SqliteRawNull() => null,
      };

    case SqliteColumnKind.decimalText:
      // Never a double: that is what breaks money.
      return switch (raw) {
        SqliteRawText(:final value) => value,
        SqliteRawInteger(:final value) => '$value',
        SqliteRawReal(:final value) => _plainDecimal(value),
        SqliteRawBlob() => fail('a decimal column holds a blob'),
        SqliteRawNull() => null,
      };

    case SqliteColumnKind.boolean:
      return switch (raw) {
        SqliteRawInteger(value: 0) => false,
        SqliteRawInteger(value: 1) => true,
        _ => fail('a boolean column holds something other than 0 or 1'),
      };

    case SqliteColumnKind.text:
      return switch (raw) {
        SqliteRawText(:final value) => value,
        SqliteRawInteger(:final value) => '$value',
        SqliteRawReal(:final value) => '$value',
        SqliteRawBlob(:final value) => _decodeUtf8(value, fail),
        SqliteRawNull() => null,
      };

    case SqliteColumnKind.blob:
      return switch (raw) {
        SqliteRawBlob(:final value) => value,
        SqliteRawText(:final value) => Uint8List.fromList(utf8.encode(value)),
        _ => fail('a blob column holds a number'),
      };

    case SqliteColumnKind.json:
      try {
        // Inside the try on purpose: utf8.decode throws FormatException on a
        // blob that is not UTF-8, and that failure has to arrive with the
        // column name attached like every other one.
        final text = switch (raw) {
          SqliteRawText(:final value) => value,
          SqliteRawBlob(:final value) => utf8.decode(value),
          SqliteRawInteger(:final value) => '$value',
          SqliteRawReal(:final value) => '$value',
          SqliteRawNull() => null,
        };
        return jsonDecode(text!);
      } on FormatException catch (error) {
        fail('not json: ${error.message}');
      }

    case SqliteColumnKind.dateTime:
      return switch (raw) {
        // Written by this driver, or any ISO 8601 text. A value with no zone
        // is a UTC wall clock: reading it as local time would make it depend
        // on the server's time zone.
        SqliteRawText(:final value) => _parseTimestamp(value, fail),
        // unixepoch() / strftime('%s'). Seconds, never milliseconds: a
        // column written by something that stores milliseconds reads as a
        // date tens of thousands of years out, which the type mapping in
        // the README says out loud rather than guessing between the two.
        SqliteRawInteger(:final value) => _timestampFromSeconds(value, fail),
        // A julian day, as SQLite's own date functions produce by default.
        SqliteRawReal(:final value) => _timestampFromJulianDay(value, fail),
        SqliteRawBlob() => fail('a timestamp column holds a blob'),
        SqliteRawNull() => null,
      };
  }
}

/// Reads [seconds] since the unix epoch as an instant in UTC.
///
/// Bounded before the multiply, not after: `seconds * 1000` wraps silently
/// at int64, so a value far enough out comes back as a perfectly plausible
/// instant -- 2^61 seconds wraps to exactly zero and reads as the epoch --
/// while one merely past what a [DateTime] holds makes the constructor throw
/// a [RangeError] that names no column. A stored number this cannot be an
/// instant is a decode failure like an unreadable timestamp string, and is
/// reported the same way, with the column and the stored value attached.
DateTime _timestampFromSeconds(int seconds, Never Function(String) fail) {
  if (seconds < -_maxSecondsSinceEpoch || seconds > _maxSecondsSinceEpoch) {
    fail('not a timestamp');
  }
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// Reads [day], a julian day number, as an instant in UTC.
///
/// The guard covers two different escapes, not one twice: [double.round]
/// throws an [UnsupportedError] for a value that is not finite, and
/// [DateTime.fromMillisecondsSinceEpoch] throws a [RangeError] past its own
/// range -- which a finite but enormous day reaches, because round() clamps
/// it to the largest int rather than refusing it. Neither carries the column.
DateTime _timestampFromJulianDay(double day, Never Function(String) fail) {
  final milliseconds = (day - _unixEpochJulianDay) * _millisecondsPerDay;
  if (!milliseconds.isFinite ||
      milliseconds < -_maxMillisecondsSinceEpoch ||
      milliseconds > _maxMillisecondsSinceEpoch) {
    fail('not a timestamp');
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds.round(), isUtc: true);
}

/// Reads a stored timestamp string as an instant in UTC.
///
/// A value that carries no zone is a UTC wall clock, so `Z` is appended
/// before parsing. Parsing it as written would give a local `DateTime` whose
/// instant depends on the machine's time zone.
DateTime _parseTimestamp(String value, Never Function(String) fail) {
  final trimmed = value.trim();
  final hasZone = RegExp(r'(?:[Zz]|[+-]\d{2}:?\d{2})$').hasMatch(trimmed);
  final parsed = DateTime.tryParse(hasZone ? trimmed : '${trimmed}Z');
  if (parsed == null) fail('not a timestamp');
  return parsed.toUtc();
}

/// Reads [bytes] as UTF-8, or fails naming the column.
///
/// TEXT affinity does not convert a blob, so a column declared TEXT can hand
/// back blob storage holding anything at all -- SQLite never checks that the
/// bytes it was given are UTF-8. Repairing them with replacement characters
/// would be the one silent corruption in the driver: the repaired string is
/// what a caller writes back, so the broken bytes would be overwritten with
/// U+FFFD and the original lost. The driver promises a value read from one
/// query can be passed to the next, so this fails instead, with the column
/// attached like every other failure here. A caller who wants the bytes
/// declares the column BLOB, or casts.
String _decodeUtf8(Uint8List bytes, Never Function(String) fail) {
  try {
    return utf8.decode(bytes);
  } on FormatException catch (error) {
    fail('not valid UTF-8: ${error.message}');
  }
}

/// The shortest decimal string that round-trips to [value], never in
/// exponent notation.
///
/// A column declared NUMERIC or DECIMAL is meant to hold digits, but SQLite
/// stores whatever it is given, so the value can arrive as a float. Plain
/// interpolation would then hand back `1e+21` or `1e-7`, which no decimal
/// parser on the other side can read. Precision already lost was lost when
/// the value was written; this only decides how the stored double is spelled.
String _plainDecimal(double value) {
  final shortest = '$value';
  final exponentAt = shortest.indexOf('e');
  if (exponentAt == -1) return shortest;

  final exponent = int.parse(shortest.substring(exponentAt + 1));
  var mantissa = shortest.substring(0, exponentAt);
  final negative = mantissa.startsWith('-');
  if (negative) mantissa = mantissa.substring(1);

  final point = mantissa.indexOf('.');
  final digits = point == -1 ? mantissa : mantissa.replaceFirst('.', '');
  // How many digits sit left of the point once the exponent is applied.
  final integerDigits = (point == -1 ? mantissa.length : point) + exponent;

  final String plain;
  if (integerDigits <= 0) {
    plain = '0.${'0' * -integerDigits}$digits';
  } else if (integerDigits >= digits.length) {
    plain = '$digits${'0' * (integerDigits - digits.length)}';
  } else {
    plain =
        '${digits.substring(0, integerDigits)}.'
        '${digits.substring(integerDigits)}';
  }
  return negative ? '-$plain' : plain;
}
