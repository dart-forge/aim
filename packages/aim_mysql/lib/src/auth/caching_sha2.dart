import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Computes the password token for the fast path of caching_sha2_password
/// authentication (over SSL/TLS).
///
/// Returns an empty list if the password is empty (the server reads a
/// zero-length auth response as no password at all, not as the hash of the
/// empty string).
///
/// The algorithm is:
///   SHA256(password) XOR SHA256( SHA256(SHA256(password)) ++ scramble )
///
/// Note: The scramble comes LAST in the concatenation for caching_sha2.
/// This differs from mysql_native_password, where it comes first.
Uint8List cachingSha2FastAuthToken({
  required String password,
  required Uint8List scramble,
}) {
  if (password.isEmpty) {
    return Uint8List(0);
  }

  // Encode password as UTF-8 and hash it
  final passwordBytes = utf8.encode(password);
  final stage1 = sha256.convert(passwordBytes).bytes;

  // Hash the hash
  final stage2 = sha256.convert(stage1).bytes;

  // Hash the concatenation: SHA256(SHA256(password)) ++ scramble
  final combined = Uint8List.fromList([...stage2, ...scramble]);
  final withScramble = sha256.convert(combined).bytes;

  // XOR stage1 with withScramble
  final result = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    result[i] = stage1[i] ^ withScramble[i];
  }

  return result;
}

/// XORs data with the scramble, repeating the scramble to cover the full
/// length of data.
///
/// Used in the public-key path of caching_sha2_password authentication
/// (over unencrypted connections).
///
/// Throws [ArgumentError] if scramble is empty.
Uint8List xorWithScramble(Uint8List data, Uint8List scramble) {
  if (scramble.isEmpty) {
    throw ArgumentError('scramble cannot be empty');
  }

  final result = Uint8List(data.length);
  for (var i = 0; i < data.length; i++) {
    result[i] = data[i] ^ scramble[i % scramble.length];
  }

  return result;
}
