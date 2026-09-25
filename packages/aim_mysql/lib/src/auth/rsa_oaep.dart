import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:crypto/crypto.dart';

/// The output size of SHA-1, in bytes. Fixed by this file's choice of hash
/// for both MGF1 and the OAEP label hash: RFC 8017 calls this `hLen`.
const int _hLen = 20;

const int _tagSequence = 0x30;
const int _tagInteger = 0x02;
const int _tagBitString = 0x03;

const String _pemBegin = '-----BEGIN PUBLIC KEY-----';
const String _pemEnd = '-----END PUBLIC KEY-----';

/// An RSA public key: a modulus and a public exponent, as sent by a MySQL
/// server that wants a password encrypted rather than sent in the clear.
final class RsaPublicKey {
  RsaPublicKey({required this.modulus, required this.exponent});

  final BigInt modulus;
  final BigInt exponent;

  /// `k`, the width in bytes of anything encrypted under this key:
  /// `(modulus.bitLength + 7) ~/ 8`.
  ///
  /// `BigInt` has no notion of its own byte width -- only its numeric
  /// value -- so this is derived from `bitLength` rather than from the
  /// length of whatever byte array the modulus happened to be parsed
  /// from.
  int get byteLength => (modulus.bitLength + 7) ~/ 8;
}

/// Parses an RSA public key out of the PEM text a MySQL server sends when
/// `caching_sha2_password` falls back to full authentication over a
/// plaintext connection.
///
/// The PEM wraps a DER-encoded SubjectPublicKeyInfo:
///
/// ```
/// SEQUENCE
///   SEQUENCE                    -- AlgorithmIdentifier
///     OID 1.2.840.113549.1.1.1  -- rsaEncryption
///     NULL
///   BIT STRING                  -- first byte is the unused-bit count (0)
///     SEQUENCE                  -- RSAPublicKey
///       INTEGER modulus
///       INTEGER publicExponent
/// ```
///
/// Throws [MySqlProtocolException] if the text is not a PEM public key, or
/// if the DER inside it cannot be parsed -- including an element whose
/// declared length runs past the bytes actually available. That is a
/// server sending something this driver cannot make sense of, not a
/// mistake by the caller.
RsaPublicKey parsePublicKeyPem(String pem) {
  final der = _decodePem(pem);

  final spki = _DerCursor(der).readTlv(_tagSequence, 'a SubjectPublicKeyInfo');
  final spkiFields = _DerCursor(spki);

  // AlgorithmIdentifier is read past without inspecting its content: the
  // server always names rsaEncryption here, and there is nothing else it
  // could name that this driver would act on differently.
  spkiFields.readTlv(_tagSequence, 'an AlgorithmIdentifier');

  final bitString = spkiFields.readTlv(_tagBitString, 'the key BIT STRING');
  if (bitString.isEmpty) {
    throw MySqlProtocolException('the public key BIT STRING is empty');
  }
  // The first byte counts unused bits in the final content byte, always 0
  // here because an RSA key is a whole number of bytes.
  final bitStringCursor = _DerCursor(Uint8List.sublistView(bitString, 1));
  final rsaKeyFields = _DerCursor(
    bitStringCursor.readTlv(_tagSequence, 'an RSAPublicKey'),
  );

  final modulus = rsaKeyFields.readTlv(_tagInteger, 'the modulus');
  final exponent = rsaKeyFields.readTlv(_tagInteger, 'the exponent');

  return RsaPublicKey(
    modulus: _bigIntFromDerInteger(modulus),
    exponent: _bigIntFromDerInteger(exponent),
  );
}

/// Strips the PEM header and footer, discards the whitespace the base64
/// body is wrapped with, and decodes it.
Uint8List _decodePem(String pem) {
  final beginIndex = pem.indexOf(_pemBegin);
  final endIndex = pem.indexOf(_pemEnd);
  if (beginIndex == -1 || endIndex == -1 || endIndex < beginIndex) {
    throw MySqlProtocolException(
      'not a PEM-encoded public key: missing BEGIN/END PUBLIC KEY markers',
    );
  }

  final body = pem.substring(beginIndex + _pemBegin.length, endIndex);
  final base64Body = body.replaceAll(RegExp(r'\s+'), '');
  try {
    return base64Decode(base64Body);
  } on FormatException catch (error) {
    throw MySqlProtocolException('the public key is not valid base64: $error');
  }
}

/// A cursor over one level of DER content, reading tag-length-value
/// elements in order and refusing to read past the bytes it was given.
///
/// Each nested element gets its own cursor over just that element's
/// content, so a length that runs past its *immediate* parent is caught
/// there rather than reading into a sibling element that happens to sit
/// next to it in memory.
final class _DerCursor {
  _DerCursor(this._data) : _offset = 0;

  final Uint8List _data;
  int _offset;

  int _readByte() {
    if (_offset >= _data.length) {
      throw MySqlProtocolException(
        'the public key ended in the middle of a DER element',
      );
    }
    return _data[_offset++];
  }

  /// Reads the next element, checks its tag against [expectedTag], and
  /// returns its content bytes. [what] names the element for the error
  /// message when the tag is wrong or the element's declared length runs
  /// past what is left at this level.
  Uint8List readTlv(int expectedTag, String what) {
    final tag = _readByte();
    if (tag != expectedTag) {
      throw MySqlProtocolException(
        'expected $what (DER tag 0x${expectedTag.toRadixString(16)}) but '
        'found tag 0x${tag.toRadixString(16)}',
      );
    }

    // DER lengths under 128 are a single byte. From 128 up, the first byte
    // is 0x80 plus a count of the length bytes that follow, big-endian --
    // 0x81 for one, 0x82 for two, and so on. A 2048-bit modulus is 256-plus
    // bytes long, so a real key always uses this long form.
    final firstLengthByte = _readByte();
    int length;
    if (firstLengthByte < 0x80) {
      length = firstLengthByte;
    } else {
      final lengthByteCount = firstLengthByte & 0x7f;
      if (lengthByteCount == 0) {
        throw MySqlProtocolException(
          'the public key uses DER indefinite-length encoding, which is '
          'not valid here',
        );
      }
      length = 0;
      for (var i = 0; i < lengthByteCount; i++) {
        length = (length << 8) | _readByte();
      }
    }

    if (length > _data.length - _offset) {
      throw MySqlProtocolException(
        'the DER element for $what claims to run past the end of its '
        'containing element',
      );
    }
    final content = Uint8List.sublistView(_data, _offset, _offset + length);
    _offset += length;
    return content;
  }
}

/// Reads the content of a DER INTEGER as a non-negative [BigInt].
///
/// DER integers are signed two's complement, so an integer with its top
/// bit set arrives with an extra leading 0x00 -- every 2048-bit RSA
/// modulus has one. That byte exists only to keep the encoding
/// non-negative, so it is dropped here rather than folded into the value.
BigInt _bigIntFromDerInteger(Uint8List content) {
  final unsigned = (content.length > 1 && content[0] == 0x00)
      ? Uint8List.sublistView(content, 1)
      : content;
  return _bigIntFromBytes(unsigned);
}

BigInt _bigIntFromBytes(Uint8List bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

/// Encodes [value] as an unsigned big-endian byte sequence exactly
/// [length] bytes wide, left-padding with zeros as needed.
///
/// `BigInt` keeps no leading zeros, so this is where a ciphertext smaller
/// than the modulus is padded back out to the key width. Skipping it
/// would put a short ciphertext on the wire.
Uint8List _bigIntToBytes(BigInt value, int length) {
  final bytes = Uint8List(length);
  var remaining = value;
  final lowByte = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (remaining & lowByte).toInt();
    remaining >>= 8;
  }
  return bytes;
}

/// MGF1 (RFC 8017, appendix B.2.1), the mask generation function OAEP
/// builds its masks from, using SHA-1 as its hash.
///
/// Concatenates `SHA1(seed ++ I2OSP(counter, 4))` for counter = 0, 1, 2...
/// and returns the first [length] bytes. The counter is 4 bytes,
/// big-endian; a narrower counter produces a mask that looks plausible but
/// is wrong. The final block is truncated, not padded, when [length] is
/// not a whole multiple of SHA-1's 20-byte output.
Uint8List mgf1(Uint8List seed, int length) {
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

/// Builds the encoded message (`EM`) for RSA-OAEP with an empty label
/// (RFC 8017, section 7.1.1), using SHA-1 for both the label hash and
/// MGF1.
///
/// ```
/// lHash  = SHA1("")
/// PS     = 0x00 repeated (k - mLen - 2*hLen - 2) times
/// DB     = lHash ++ PS ++ 0x01 ++ message
/// DB'    = DB  XOR MGF1(seed, k - hLen - 1)
/// seed'  = seed XOR MGF1(DB', hLen)
/// EM     = 0x00 ++ seed' ++ DB'
/// ```
///
/// [seed] is a parameter rather than something this function invents,
/// because that is how OAEP is defined: encoding is a deterministic
/// function of the seed, and choosing the seed is the caller's job (see
/// [rsaOaepEncrypt]). That split is what makes the encoding checkable
/// against a fixed seed in tests.
///
/// Throws [ArgumentError] if [seed] is not exactly [_hLen] (20) bytes, or
/// if [message] is too long to fit in a [k]-byte block -- both are
/// mistakes by the caller, not something misread from the server.
Uint8List oaepEncode({
  required Uint8List message,
  required Uint8List seed,
  required int k,
}) {
  if (seed.length != _hLen) {
    throw ArgumentError.value(
      seed.length,
      'seed.length',
      'the OAEP seed must be exactly $_hLen bytes (the SHA-1 output size)',
    );
  }

  final maxMessageLength = k - 2 * _hLen - 2;
  if (message.length > maxMessageLength) {
    throw ArgumentError.value(
      message.length,
      'message.length',
      'too long to OAEP-encode into a $k-byte block; the maximum is '
          '$maxMessageLength bytes',
    );
  }

  final lHash = sha1.convert(const <int>[]).bytes;
  final psLength = k - message.length - 2 * _hLen - 2;
  final db = Uint8List.fromList([
    ...lHash,
    ...List.filled(psLength, 0x00),
    0x01,
    ...message,
  ]);

  final dbMask = mgf1(seed, k - _hLen - 1);
  final maskedDb = Uint8List(db.length);
  for (var i = 0; i < db.length; i++) {
    maskedDb[i] = db[i] ^ dbMask[i];
  }

  final seedMask = mgf1(maskedDb, _hLen);
  final maskedSeed = Uint8List(_hLen);
  for (var i = 0; i < _hLen; i++) {
    maskedSeed[i] = seed[i] ^ seedMask[i];
  }

  return Uint8List.fromList([0x00, ...maskedSeed, ...maskedDb]);
}

/// The RSA primitive: reads [em] as an unsigned big-endian integer and
/// raises it to [key]'s public exponent modulo its modulus.
///
/// Throws [ArgumentError] if [em] is not exactly [RsaPublicKey.byteLength]
/// bytes -- a mistake by the caller, since [oaepEncode] always produces a
/// block of exactly that width.
///
/// The result is left-padded with zeros back out to that same width:
/// `BigInt` drops leading zeros, so without this a ciphertext smaller
/// than the modulus would go out one or more bytes short.
Uint8List rsaEncryptPrimitive(Uint8List em, RsaPublicKey key) {
  final k = key.byteLength;
  if (em.length != k) {
    throw ArgumentError.value(
      em.length,
      'em.length',
      'must equal the key width ($k bytes)',
    );
  }

  final m = _bigIntFromBytes(em);
  final c = m.modPow(key.exponent, key.modulus);
  return _bigIntToBytes(c, k);
}

/// Encrypts [message] for [key] with RSA-OAEP: a fresh random seed, OAEP
/// encoding, then the RSA primitive.
///
/// This is the encryption a MySQL client performs on the password (after
/// XOR-ing it with the scramble) when `caching_sha2_password` falls back
/// to full authentication over a connection without TLS.
Uint8List rsaOaepEncrypt({
  required Uint8List message,
  required RsaPublicKey key,
}) {
  final seed = _randomBytes(_hLen);
  final em = oaepEncode(message: message, seed: seed, k: key.byteLength);
  return rsaEncryptPrimitive(em, key);
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList([
    for (var i = 0; i < length; i++) random.nextInt(256),
  ]);
}
