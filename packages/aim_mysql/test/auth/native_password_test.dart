import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_mysql/src/auth/native_password.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

Uint8List scrambleOf(int fill) => Uint8List.fromList(List.filled(20, fill));

void main() {
  test('is 20 bytes, the width of SHA-1', () {
    expect(
      nativePasswordToken(password: 'secret', scramble: scrambleOf(0x41)),
      hasLength(20),
    );
  });

  test('an empty password produces an empty token', () {
    // The server reads a zero-length auth response as "no password", which
    // is different from the hash of the empty string.
    expect(
      nativePasswordToken(password: '', scramble: scrambleOf(0x41)),
      isEmpty,
    );
  });

  test('a different scramble gives a different token', () {
    // The whole point: a token captured from one connection is useless on
    // the next.
    expect(
      nativePasswordToken(password: 'secret', scramble: scrambleOf(0x41)),
      isNot(
        nativePasswordToken(password: 'secret', scramble: scrambleOf(0x42)),
      ),
    );
  });

  test('a different password gives a different token', () {
    expect(
      nativePasswordToken(password: 'secret', scramble: scrambleOf(0x41)),
      isNot(nativePasswordToken(password: 'other', scramble: scrambleOf(0x41))),
    );
  });

  test('matches the algorithm, computed independently here', () {
    // Spelled out rather than compared against a golden value, so this
    // test says what the algorithm *is* and would catch the two halves of
    // the concatenation being swapped.
    const password = 'secret';
    final scramble = scrambleOf(0x41);

    final stage1 = sha1.convert(utf8.encode(password)).bytes;
    final stage2 = sha1.convert(stage1).bytes;
    final withScramble = sha1.convert([...scramble, ...stage2]).bytes;
    final expected = [for (var i = 0; i < 20; i++) stage1[i] ^ withScramble[i]];

    expect(
      nativePasswordToken(password: password, scramble: scramble),
      expected,
    );
  });

  test('the scramble comes first in the concatenation', () {
    // Swapping the two halves keeps the length and the shape, so nothing
    // else here would notice. The server would simply refuse the login.
    const password = 'secret';
    final scramble = scrambleOf(0x41);

    final stage1 = sha1.convert(utf8.encode(password)).bytes;
    final stage2 = sha1.convert(stage1).bytes;
    final swapped = sha1.convert([...stage2, ...scramble]).bytes;
    final wrong = [for (var i = 0; i < 20; i++) stage1[i] ^ swapped[i]];

    expect(
      nativePasswordToken(password: password, scramble: scramble),
      isNot(wrong),
    );
  });

  test('a non-ASCII password is hashed as UTF-8', () {
    // The connection asks for utf8mb4, so the password travels as UTF-8.
    // Encoding it as Latin-1 would work for ASCII passwords and fail for
    // everyone else.
    final stage1 = sha1.convert(utf8.encode('パスワード')).bytes;
    final stage2 = sha1.convert(stage1).bytes;
    final withScramble = sha1.convert([...scrambleOf(0x41), ...stage2]).bytes;

    expect(nativePasswordToken(password: 'パスワード', scramble: scrambleOf(0x41)), [
      for (var i = 0; i < 20; i++) stage1[i] ^ withScramble[i],
    ]);
  });
}
