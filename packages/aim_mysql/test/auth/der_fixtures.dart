import 'dart:convert';
import 'dart:typed_data';

/// Wraps [der] as a PEM public key.
String pemPublicKey(List<int> der) =>
    '-----BEGIN PUBLIC KEY-----\n${base64.encode(der)}\n'
    '-----END PUBLIC KEY-----\n';

/// A SubjectPublicKeyInfo carrying [modulus] and [exponent] as DER INTEGER
/// contents — passed in already sign-extended, exactly as a real key has them.
Uint8List subjectPublicKeyInfo(List<int> modulus, List<int> exponent) {
  final rsaKey = derElement(0x30, [
    ...derElement(0x02, modulus),
    ...derElement(0x02, exponent),
  ]);
  return derElement(0x30, [
    ...derElement(0x30, [
      ...derElement(0x06, [
        0x2a,
        0x86,
        0x48,
        0x86,
        0xf7,
        0x0d,
        0x01,
        0x01,
        0x01,
      ]),
      ...derElement(0x05, const []),
    ]),
    ...derElement(0x03, [0x00, ...rsaKey]),
  ]);
}

/// One DER element: tag, length in whichever form fits, then the content.
Uint8List derElement(int tag, List<int> content) {
  final length = content.length;
  final header = switch (length) {
    < 0x80 => [tag, length],
    < 0x100 => [tag, 0x81, length],
    _ => [tag, 0x82, length >> 8, length & 0xff],
  };
  return Uint8List.fromList([...header, ...content]);
}

/// A 2048-bit public key, the shape a real MySQL server hands over.
///
/// Not a real key — nothing decrypts what it encrypts. It is here so the
/// encryption path can be exercised at the right width.
String get samplePublicKeyPem => pemPublicKey(
  subjectPublicKeyInfo(
    Uint8List.fromList([0x00, 0xc0, ...List.filled(255, 0x5a)]),
    [0x01, 0x00, 0x01],
  ),
);
