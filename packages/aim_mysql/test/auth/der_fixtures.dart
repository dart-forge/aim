import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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

/// A 2048-bit public key with the same modulus as [samplePublicKeyPem],
/// but an exponent of 1 -- raising anything to the power 1 leaves it
/// unchanged, so RSA does nothing to whatever OAEP encoding is raised to
/// this key's power. The "ciphertext" produced against this key is the
/// OAEP encoding itself, byte for byte, and [oaepRecover] can unmask it
/// back into the message that went in.
///
/// Not a key: nothing encrypted under it is safe, and a test using it is
/// not testing encryption. It is a window onto what a real key would have
/// hidden, useful only because these tests have nothing to hide from
/// themselves.
String get readableKeyPem => pemPublicKey(
  subjectPublicKeyInfo(
    Uint8List.fromList([0x00, 0xc0, ...List.filled(255, 0x5a)]),
    [0x01],
  ),
);

/// MGF1 (RFC 8017, appendix B.2.1) against `sha1`, computed directly here
/// from `package:crypto` rather than by calling anything under `lib/`.
/// Used only by [oaepRecover], so that recovering a message this package
/// encoded does not depend on the same mask generation it is checking.
Uint8List _mgf1(Uint8List seed, int length) {
  final output = <int>[];
  for (var counter = 0; output.length < length; counter++) {
    output.addAll(
      sha1.convert([
        ...seed,
        (counter >> 24) & 0xff,
        (counter >> 16) & 0xff,
        (counter >> 8) & 0xff,
        counter & 0xff,
      ]).bytes,
    );
  }
  return Uint8List.fromList(output.sublist(0, length));
}

/// Reverses OAEP's masking against [encoded] -- an encoding produced
/// under [readableKeyPem], whose exponent-1 RSA step leaves it untouched
/// -- and returns the message that was encoded.
///
/// Recomputes both masks with [_mgf1] rather than anything from
/// `lib/src/auth/rsa_oaep.dart`, so this reads back what a test sent
/// independently of the code under test instead of round-tripping through
/// it. Does not check the label hash at the front of the decoded data
/// block: a fixture reading back its own output has nothing to defend
/// against, only a value to recover.
Uint8List oaepRecover(Uint8List encoded) {
  const hLen = 20;
  final k = encoded.length;
  final maskedSeed = Uint8List.sublistView(encoded, 1, 1 + hLen);
  final maskedDb = Uint8List.sublistView(encoded, 1 + hLen);

  final seedMask = _mgf1(maskedDb, hLen);
  final seed = Uint8List(hLen);
  for (var i = 0; i < hLen; i++) {
    seed[i] = maskedSeed[i] ^ seedMask[i];
  }

  final dbMask = _mgf1(seed, k - hLen - 1);
  final db = Uint8List(maskedDb.length);
  for (var i = 0; i < db.length; i++) {
    db[i] = maskedDb[i] ^ dbMask[i];
  }

  // db is lHash (hLen bytes) ++ zero padding ++ 0x01 ++ message.
  var i = hLen;
  while (db[i] == 0x00) {
    i++;
  }
  return Uint8List.sublistView(db, i + 1);
}
