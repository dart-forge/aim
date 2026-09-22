import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/auth/rsa_oaep.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'der_fixtures.dart';

void main() {
  group('reading the public key', () {
    test('a key small enough to check by hand', () {
      // Built here rather than pasted, so every byte is accounted for:
      // SEQUENCE { AlgorithmIdentifier, BIT STRING { SEQUENCE { n, e } } }
      // with n = 259 and e = 65537.
      final der = Uint8List.fromList([
        0x30, 0x1d, //                       SEQUENCE, 29 bytes
        0x30, 0x0d, //                         SEQUENCE, 13 bytes
        0x06, 0x09, //                           OID, 9 bytes
        0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, // rsaEncryption
        0x05, 0x00, //                           NULL
        0x03, 0x0c, //                         BIT STRING, 12 bytes
        0x00, //                                  0 unused bits
        0x30, 0x09, //                           SEQUENCE, 9 bytes
        0x02, 0x02, 0x01, 0x03, //                 INTEGER 259
        0x02, 0x03, 0x01, 0x00, 0x01, //           INTEGER 65537
      ]);

      final key = parsePublicKeyPem(pemPublicKey(der));

      expect(key.modulus, BigInt.from(259));
      expect(key.exponent, BigInt.from(65537));
    });

    test('strips the sign byte from a modulus with its high bit set', () {
      // DER INTEGERs are signed, so a real 2048-bit modulus always arrives
      // with a leading zero. Keeping it would make the number 256 times too
      // large and every ciphertext wrong.
      final modulus = Uint8List.fromList([0x00, 0xff, 0xff]);

      final key = parsePublicKeyPem(
        pemPublicKey(subjectPublicKeyInfo(modulus, [0x01, 0x00, 0x01])),
      );

      expect(key.modulus, BigInt.from(0xffff));
    });

    test('reads a real-sized key, which needs long-form lengths', () {
      // Above 127 bytes DER switches to 0x82 followed by a two-byte length.
      // A reader that only handles the short form works on every test above
      // and fails on every real key.
      final modulus = Uint8List.fromList([
        0x00,
        0xc0,
        ...List.filled(255, 0x5a),
      ]);

      final key = parsePublicKeyPem(
        pemPublicKey(subjectPublicKeyInfo(modulus, [0x01, 0x00, 0x01])),
      );

      expect(key.modulus.bitLength, 2048);
      expect(key.exponent, BigInt.from(65537));
      expect(key.byteLength, 256, reason: 'k, the width of a ciphertext');
    });

    test('byteLength rounds up for a modulus that is not a whole byte', () {
      final key = parsePublicKeyPem(
        pemPublicKey(subjectPublicKeyInfo([0x01, 0x03], [0x03])),
      );

      expect(key.modulus.bitLength, 9);
      expect(key.byteLength, 2);
    });

    test('tolerates the line wrapping openssl produces', () {
      final modulus = Uint8List.fromList([
        0x00,
        0xc0,
        ...List.filled(255, 0x5a),
      ]);
      final der = subjectPublicKeyInfo(modulus, [0x01, 0x00, 0x01]);
      final wrapped = RegExp('.{1,64}')
          .allMatches(base64.encode(der))
          .map((m) => m[0])
          .join('\n');
      final pem =
          '-----BEGIN PUBLIC KEY-----\n$wrapped\n-----END PUBLIC KEY-----\n';

      expect(parsePublicKeyPem(pem).exponent, BigInt.from(65537));
    });

    test('tolerates CRLF line endings', () {
      final der = subjectPublicKeyInfo([0x01, 0x03], [0x01, 0x00, 0x01]);
      final pem =
          '-----BEGIN PUBLIC KEY-----\r\n'
          '${base64.encode(der)}\r\n'
          '-----END PUBLIC KEY-----\r\n';

      expect(parsePublicKeyPem(pem).modulus, BigInt.from(259));
    });

    test('refuses something that is not a PEM public key', () {
      expect(
        () => parsePublicKeyPem('not a key'),
        throwsA(isA<MySqlProtocolException>()),
      );
    });

    test('refuses a truncated key rather than reading past the end', () {
      final der = subjectPublicKeyInfo([0x01, 0x03], [0x01, 0x00, 0x01]);
      final truncated = Uint8List.sublistView(der, 0, der.length - 3);

      expect(
        () => parsePublicKeyPem(pemPublicKey(truncated)),
        throwsA(isA<MySqlProtocolException>()),
      );
    });
  });

  group('MGF1', () {
    final seed = Uint8List.fromList(utf8.encode('seed'));

    test('produces exactly the requested length', () {
      expect(mgf1(seed, 1), hasLength(1));
      expect(mgf1(seed, 20), hasLength(20));
      expect(mgf1(seed, 21), hasLength(21));
      expect(mgf1(seed, 235), hasLength(235));
    });

    test('the first block is SHA1(seed ++ 0x00000000)', () {
      // Spelled out because the counter width is the easiest thing to get
      // wrong, and a one-byte counter produces a plausible-looking wrong
      // answer.
      expect(
        mgf1(seed, 20),
        sha1.convert([...seed, 0x00, 0x00, 0x00, 0x00]).bytes,
      );
    });

    test('the second block is SHA1(seed ++ 0x00000001)', () {
      expect(
        mgf1(seed, 40).sublist(20),
        sha1.convert([...seed, 0x00, 0x00, 0x00, 0x01]).bytes,
      );
    });

    test('truncates the last block rather than padding it', () {
      expect(
        mgf1(seed, 25).sublist(20),
        sha1.convert([...seed, 0x00, 0x00, 0x00, 0x01]).bytes.sublist(0, 5),
      );
    });

    test('a different seed gives a different result', () {
      expect(mgf1(seed, 20), isNot(mgf1(Uint8List.fromList([0x00]), 20)));
    });

    test('an empty seed is allowed', () {
      // The algorithm does not forbid it, and refusing would be a surprise.
      expect(mgf1(Uint8List(0), 20), hasLength(20));
    });
  });

  group('the OAEP encoding', () {
    final seed = Uint8List.fromList(List.filled(20, 0x11));
    final message = Uint8List.fromList([...utf8.encode('secret'), 0]);

    test('is exactly k bytes and starts with a zero', () {
      // The leading zero is what keeps EM below the modulus.
      final em = oaepEncode(message: message, seed: seed, k: 256);

      expect(em, hasLength(256));
      expect(em[0], 0);
    });

    test('unmasks to lHash ++ zeros ++ 0x01 ++ message', () {
      // The masks are recomputed here from the spec, with sha1 directly
      // rather than through this library's mgf1, so this checks the
      // encoding against the algorithm and not against itself.
      const k = 256;
      const hLen = 20;
      final em = oaepEncode(message: message, seed: seed, k: k);

      final maskedSeed = Uint8List.sublistView(em, 1, 1 + hLen);
      final maskedDb = Uint8List.sublistView(em, 1 + hLen);

      final seedMask = _mgf1WithSha1(maskedDb, hLen);
      final recoveredSeed = Uint8List.fromList([
        for (var i = 0; i < hLen; i++) maskedSeed[i] ^ seedMask[i],
      ]);
      expect(recoveredSeed, seed, reason: 'the seed round-trips');

      final dbMask = _mgf1WithSha1(recoveredSeed, k - hLen - 1);
      final db = Uint8List.fromList([
        for (var i = 0; i < maskedDb.length; i++) maskedDb[i] ^ dbMask[i],
      ]);

      final lHash = sha1.convert(const []).bytes;
      final padding = k - message.length - 2 * hLen - 2;

      expect(db.sublist(0, hLen), lHash, reason: 'lHash of the empty label');
      expect(
        db.sublist(hLen, hLen + padding),
        everyElement(0),
        reason: 'the zero padding',
      );
      expect(db[hLen + padding], 0x01, reason: 'the separator');
      expect(db.sublist(hLen + padding + 1), message);
    });

    test('a different seed gives a completely different EM', () {
      final a = oaepEncode(message: message, seed: seed, k: 256);
      final b = oaepEncode(
        message: message,
        seed: Uint8List.fromList(List.filled(20, 0x22)),
        k: 256,
      );

      expect(a, isNot(b));
    });

    test('accepts a message of exactly the maximum length', () {
      // k - 2*hLen - 2, the point where the zero padding disappears.
      final largest = Uint8List(256 - 2 * 20 - 2);

      expect(oaepEncode(message: largest, seed: seed, k: 256), hasLength(256));
    });

    test('refuses a message one byte too long', () {
      // Continuing would overflow DB and produce a ciphertext the server
      // rejects with no explanation.
      final tooLong = Uint8List(256 - 2 * 20 - 1);

      expect(
        () => oaepEncode(message: tooLong, seed: seed, k: 256),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('refuses a seed that is not 20 bytes', () {
      expect(
        () => oaepEncode(message: message, seed: Uint8List(19), k: 256),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the RSA primitive', () {
    // The textbook key: n = 61 * 53 = 3233, e = 17. Small enough that the
    // expected ciphertext can be checked by hand.
    final small = RsaPublicKey(
      modulus: BigInt.from(3233),
      exponent: BigInt.from(17),
    );

    test('65 encrypts to 2790', () {
      expect(rsaEncryptPrimitive(Uint8List.fromList([0x00, 65]), small), [
        0x0a,
        0xe6,
      ]);
    });

    test('pads the result to k bytes on the left', () {
      // 1^17 mod 3233 is 1. Returning one byte instead of two would make
      // every short ciphertext the wrong length on the wire.
      expect(rsaEncryptPrimitive(Uint8List.fromList([0x00, 0x01]), small), [
        0x00,
        0x01,
      ]);
    });

    test('refuses an EM that is not k bytes', () {
      expect(
        () => rsaEncryptPrimitive(Uint8List.fromList([65]), small),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('encrypting end to end', () {
    final key = parsePublicKeyPem(samplePublicKeyPem);

    test('produces a ciphertext of the key width', () {
      expect(
        rsaOaepEncrypt(
          message: Uint8List.fromList([...utf8.encode('secret'), 0]),
          key: key,
        ),
        hasLength(256),
      );
    });

    test('is different every time, because the seed is random', () {
      // If two calls ever match, the seed is not being generated.
      final message = Uint8List.fromList([...utf8.encode('secret'), 0]);
      final results = {
        for (var i = 0; i < 5; i++)
          base64.encode(rsaOaepEncrypt(message: message, key: key)),
      };

      expect(results, hasLength(5));
    });
  });
}

/// MGF1 written from the spec, for checking the library's own against.
Uint8List _mgf1WithSha1(Uint8List seed, int length) {
  final out = <int>[];
  for (var counter = 0; out.length < length; counter++) {
    out.addAll(
      sha1.convert([
        ...seed,
        (counter >> 24) & 0xff,
        (counter >> 16) & 0xff,
        (counter >> 8) & 0xff,
        counter & 0xff,
      ]).bytes,
    );
  }
  return Uint8List.fromList(out.sublist(0, length));
}
