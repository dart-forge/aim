import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Computes the password token for mysql_native_password authentication.
///
/// Returns an empty list if the password is empty (the server reads a
/// zero-length auth response as no password at all, not as the hash of the
/// empty string).
///
/// The algorithm is:
///   SHA1(password) XOR SHA1( scramble ++ SHA1(SHA1(password)) )
///
/// Note: The scramble comes FIRST in the concatenation for native password.
/// This differs from caching_sha2_password, where it comes last.
Uint8List nativePasswordToken({
  required String password,
  required Uint8List scramble,
}) {
  if (password.isEmpty) {
    return Uint8List(0);
  }

  // Encode password as UTF-8 and hash it
  final passwordBytes = utf8.encode(password);
  final stage1 = sha1.convert(passwordBytes).bytes;

  // Hash the hash
  final stage2 = sha1.convert(stage1).bytes;

  // Hash the concatenation: scramble ++ SHA1(SHA1(password))
  final combined = Uint8List.fromList([...scramble, ...stage2]);
  final withScramble = sha1.convert(combined).bytes;

  // XOR stage1 with withScramble
  final result = Uint8List(20);
  for (var i = 0; i < 20; i++) {
    result[i] = stage1[i] ^ withScramble[i];
  }

  return result;
}
