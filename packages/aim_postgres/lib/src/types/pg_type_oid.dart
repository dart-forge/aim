/// Built-in PostgreSQL type OIDs (`pg_type.oid`) that the driver decodes.
///
/// Values are stable across PostgreSQL versions. Anything not listed here is
/// returned to the caller as the raw text (see `PgTypeDecoder.forOid`).
abstract final class PgTypeOid {
  static const int bool_ = 16;
  static const int bytea = 17;
  static const int name = 19;
  static const int int8 = 20;
  static const int int2 = 21;
  static const int int4 = 23;
  static const int text = 25;
  static const int oid = 26;
  static const int json = 114;
  static const int float4 = 700;
  static const int float8 = 701;
  static const int bpchar = 1042;
  static const int varchar = 1043;
  static const int date = 1082;
  static const int time = 1083;
  static const int timestamp = 1114;
  static const int timestamptz = 1184;
  static const int interval = 1186;
  static const int timetz = 1266;
  static const int numeric = 1700;
  static const int uuid = 2950;
  static const int jsonb = 3802;

  // One-dimensional array types, keyed by their element type.
  static const int boolArray = 1000;
  static const int byteaArray = 1001;
  static const int nameArray = 1003;
  static const int int2Array = 1005;
  static const int int4Array = 1007;
  static const int textArray = 1009;
  static const int bpcharArray = 1014;
  static const int varcharArray = 1015;
  static const int int8Array = 1016;
  static const int float4Array = 1021;
  static const int float8Array = 1022;
  static const int oidArray = 1028;
  static const int jsonArray = 199;
  static const int timestampArray = 1115;
  static const int dateArray = 1182;
  static const int timeArray = 1183;
  static const int timestamptzArray = 1185;
  static const int intervalArray = 1187;
  static const int numericArray = 1231;
  static const int timetzArray = 1270;
  static const int uuidArray = 2951;
  static const int jsonbArray = 3807;

  /// Maps an array type OID to its element type OID.
  static const Map<int, int> arrayElement = {
    boolArray: bool_,
    byteaArray: bytea,
    nameArray: name,
    int2Array: int2,
    int4Array: int4,
    textArray: text,
    bpcharArray: bpchar,
    varcharArray: varchar,
    int8Array: int8,
    float4Array: float4,
    float8Array: float8,
    oidArray: oid,
    jsonArray: json,
    timestampArray: timestamp,
    dateArray: date,
    timeArray: time,
    timestamptzArray: timestamptz,
    intervalArray: interval,
    numericArray: numeric,
    timetzArray: timetz,
    uuidArray: uuid,
    jsonbArray: jsonb,
  };
}
