import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_mysql/src/auth/caching_sha2.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

Uint8List scrambleOf(int fill) => Uint8List.fromList(List.filled(20, fill));

void main() {
  group('the fast-path token', () {
    test('is 32 bytes, the width of SHA-256', () {
      expect(
        cachingSha2FastAuthToken(
          password: 'secret',
          scramble: scrambleOf(0x41),
        ),
        hasLength(32),
      );
    });

    test('an empty password produces an empty token', () {
      expect(
        cachingSha2FastAuthToken(password: '', scramble: scrambleOf(0x41)),
        isEmpty,
      );
    });

    test('matches the algorithm, computed independently here', () {
      const password = 'secret';
      final scramble = scrambleOf(0x41);

      final stage1 = sha256.convert(utf8.encode(password)).bytes;
      final stage2 = sha256.convert(stage1).bytes;
      final withScramble = sha256.convert([...stage2, ...scramble]).bytes;
      final expected = [
        for (var i = 0; i < 32; i++) stage1[i] ^ withScramble[i],
      ];

      expect(
        cachingSha2FastAuthToken(password: password, scramble: scramble),
        expected,
      );
    });

    test('the scramble comes last, unlike native password', () {
      // The two plugins concatenate in opposite orders. Getting this one
      // backwards produces a token of the right length that the server
      // refuses, with nothing in the shape to suggest why.
      const password = 'secret';
      final scramble = scrambleOf(0x41);

      final stage1 = sha256.convert(utf8.encode(password)).bytes;
      final stage2 = sha256.convert(stage1).bytes;
      final swapped = sha256.convert([...scramble, ...stage2]).bytes;
      final wrong = [for (var i = 0; i < 32; i++) stage1[i] ^ swapped[i]];

      expect(
        cachingSha2FastAuthToken(password: password, scramble: scramble),
        isNot(wrong),
      );
    });

    test('a different scramble gives a different token', () {
      expect(
        cachingSha2FastAuthToken(
          password: 'secret',
          scramble: scrambleOf(0x41),
        ),
        isNot(
          cachingSha2FastAuthToken(
            password: 'secret',
            scramble: scrambleOf(0x42),
          ),
        ),
      );
    });

    test('a non-ASCII password is hashed as UTF-8', () {
      // The same property the native password tests check, and it applies
      // here for the same reason: Latin-1 works for every ASCII password
      // and fails for everyone else, so an ASCII-only suite cannot catch
      // it. Both plugins need the case; only one of them had it.
      final stage1 = sha256.convert(utf8.encode('パスワード')).bytes;
      final stage2 = sha256.convert(stage1).bytes;
      final withScramble = sha256.convert([
        ...stage2,
        ...scrambleOf(0x41),
      ]).bytes;

      expect(
        cachingSha2FastAuthToken(password: 'パスワード', scramble: scrambleOf(0x41)),
        [for (var i = 0; i < 32; i++) stage1[i] ^ withScramble[i]],
      );
    });
  });

  group('xorWithScramble', () {
    test('repeats the scramble to cover the data', () {
      // The password sent on the public-key path is longer than the
      // scramble, so the scramble wraps.
      //
      // The scramble's bytes are deliberately all different. A uniform
      // scramble would make this test pass against a hard-coded width, an
      // off-by-one, or almost any in-range indexing at all, because every
      // index gives the same byte — the test would read as if it checked
      // the wrapping while checking nothing about it.
      final scramble = Uint8List.fromList(List.generate(20, (i) => i + 1));
      final data = Uint8List.fromList(List.filled(50, 0x00));

      final result = xorWithScramble(data, scramble);

      expect(result, hasLength(50));
      expect(result, [
        for (var i = 0; i < 50; i++) scramble[i % 20],
      ], reason: 'XOR with zero is the scramble itself, laid out repeating');
    });

    test('is its own inverse', () {
      // Which is how the server recovers the password after decrypting.
      final data = Uint8List.fromList([...utf8.encode('secret'), 0]);
      final scramble = scrambleOf(0x5a);

      expect(xorWithScramble(xorWithScramble(data, scramble), scramble), data);
    });

    test('wraps at the scramble length, not at 20 always', () {
      final data = Uint8List.fromList([0xff, 0xff, 0xff]);
      final scramble = Uint8List.fromList([0x01, 0x02]);

      expect(xorWithScramble(data, scramble), [0xfe, 0xfd, 0xfe]);
    });

    test('refuses an empty scramble rather than dividing by zero', () {
      expect(
        () => xorWithScramble(Uint8List.fromList([0x01]), Uint8List(0)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
