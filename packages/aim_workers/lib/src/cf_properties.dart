import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Cloudflare's `request.cf` metadata (`IncomingRequestCfProperties`).
class CfProperties {
  final JSObject raw;

  CfProperties(this.raw);

  String? get country => _string('country');
  String? get colo => _string('colo');
  String? get city => _string('city');
  String? get region => _string('region');
  String? get regionCode => _string('regionCode');
  String? get continent => _string('continent');
  String? get timezone => _string('timezone');
  String? get postalCode => _string('postalCode');
  double? get latitude => _double('latitude');
  double? get longitude => _double('longitude');
  int? get asn => _int('asn');
  String? get asOrganization => _string('asOrganization');
  String? get httpProtocol => _string('httpProtocol');
  String? get tlsVersion => _string('tlsVersion');
  String? get tlsCipher => _string('tlsCipher');

  /// Any other property as a string (e.g. `botManagement` sub-fields are not
  /// covered), or `null` when absent or not a string.
  String? string(String name) => _string(name);

  String? _string(String name) {
    final value = raw.getProperty(name.toJS);
    return value.isA<JSString>() ? (value as JSString).toDart : null;
  }

  double? _double(String name) {
    final value = raw.getProperty(name.toJS);
    if (value.isA<JSNumber>()) return (value as JSNumber).toDartDouble;
    if (value.isA<JSString>())
      return double.tryParse((value as JSString).toDart);
    return null;
  }

  int? _int(String name) {
    final value = raw.getProperty(name.toJS);
    if (value.isA<JSNumber>()) return (value as JSNumber).toDartInt;
    if (value.isA<JSString>()) return int.tryParse((value as JSString).toDart);
    return null;
  }
}
