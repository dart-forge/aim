import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_mysql/src/auth/auth.dart';
import 'package:aim_mysql/src/auth/caching_sha2.dart';
import 'package:aim_mysql/src/auth/native_password.dart';
import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/handshake.dart';
import 'package:aim_mysql/src/protocol/wire.dart';
import 'package:test/test.dart';

import 'der_fixtures.dart';

/// A transport that hands back a scripted list of packets and records what
/// was sent.
class ScriptedTransport implements AuthTransport {
  ScriptedTransport(this._script, {this.isSecure = false});

  final List<Uint8List> _script;
  final sent = <Uint8List>[];
  int _position = 0;

  @override
  final bool isSecure;

  @override
  Future<void> send(Uint8List payload) async => sent.add(payload);

  @override
  Future<Uint8List> receive() async {
    if (_position >= _script.length) {
      // Loudly, rather than hanging the suite: an exchange that asks for
      // more packets than the test scripted has gone off the rails.
      throw StateError(
        'the exchange wanted packet ${_position + 1}, the test scripted '
        '${_script.length}',
      );
    }
    return _script[_position++];
  }
}

Uint8List okPacket() =>
    Uint8List.fromList([0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00]);

Uint8List errPacket(int code, String message) => Uint8List.fromList([
  0xff,
  code & 0xff,
  code >> 8,
  0x23,
  ...'28000'.codeUnits,
  ...message.codeUnits,
]);

Uint8List authSwitch(String plugin, Uint8List scramble) =>
    Uint8List.fromList([0xfe, ...plugin.codeUnits, 0x00, ...scramble, 0x00]);

Uint8List authMoreData(List<int> data) => Uint8List.fromList([0x01, ...data]);

/// The password as it travels on the cleartext full-auth path.
Uint8List nulTerminated(String password) =>
    Uint8List.fromList([...utf8.encode(password), 0]);

bool containsBytes(List<int> haystack, List<int> needle) {
  // An empty needle is "contained" in everything, so a caller that passes
  // one gets an assertion that cannot fail. That is not hypothetical: an
  // earlier version of the no-password test below asked whether the sent
  // packet contained the empty-password token, which IS empty — so the
  // check passed no matter what the driver sent. Refuse it here rather
  // than let the next caller find out the same way.
  if (needle.isEmpty) {
    throw ArgumentError.value(needle, 'needle', 'would match anything');
  }
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

final scramble = Uint8List.fromList(List.filled(20, 0x41));
final otherScramble = Uint8List.fromList(List.filled(20, 0x42));

Future<void> run(
  ScriptedTransport transport, {
  String plugin = 'caching_sha2_password',
  String password = 'secret',
  String? database,
}) => authenticate(
  transport: transport,
  capabilities:
      Capabilities.protocol41 |
      Capabilities.secureConnection |
      Capabilities.pluginAuth |
      Capabilities.pluginAuthLenencClientData |
      (database == null ? 0 : Capabilities.connectWithDb),
  user: 'test',
  password: password,
  database: database,
  initialPluginName: plugin,
  initialScramble: scramble,
);

void main() {
  group('mysql_native_password', () {
    test('one packet out, an OK back, done', () {
      final transport = ScriptedTransport([okPacket()]);

      expect(run(transport, plugin: 'mysql_native_password'), completes);
    });

    test(
      'the first packet is a full handshake response, not a bare token',
      () async {
        // Only the first auth packet is wrapped. Sending a bare token here
        // would leave the server reading the token as capability flags.
        final transport = ScriptedTransport([okPacket()]);

        await run(transport, plugin: 'mysql_native_password');

        expect(transport.sent, hasLength(1));
        expect(
          transport.sent.single.length,
          greaterThan(32),
          reason: 'the 32-byte prefix plus a user, a token and a plugin name',
        );
        expect(
          containsBytes(transport.sent.single, utf8.encode('test')),
          isTrue,
          reason: 'the user name is in there',
        );
        expect(
          containsBytes(
            transport.sent.single,
            nativePasswordToken(password: 'secret', scramble: scramble),
          ),
          isTrue,
          reason: 'and so is the token for the scramble we were given',
        );
      },
    );

    test('more data during native password is a protocol failure', () {
      // The plugin has no second round. One arriving means the packet was
      // misread.
      final transport = ScriptedTransport([
        authMoreData([0x04]),
      ]);

      expect(
        run(transport, plugin: 'mysql_native_password'),
        throwsA(isA<MySqlProtocolException>()),
      );
    });
  });

  group('caching_sha2_password, cache hit', () {
    test('0x03 then OK, with nothing sent in between', () async {
      // The fast path is one round trip. An extra packet here desynchronises
      // the connection for good.
      final transport = ScriptedTransport([
        authMoreData([0x03]),
        okPacket(),
      ]);

      await run(transport);

      expect(transport.sent, hasLength(1));
    });

    test('the token is the SHA-256 one, not the SHA-1 one', () async {
      final transport = ScriptedTransport([
        authMoreData([0x03]),
        okPacket(),
      ]);

      await run(transport);

      expect(
        containsBytes(
          transport.sent.single,
          cachingSha2FastAuthToken(password: 'secret', scramble: scramble),
        ),
        isTrue,
      );
    });
  });

  group('caching_sha2_password, full auth over TLS', () {
    test('sends the password in the clear, NUL-terminated', () async {
      // Safe here and only here: the socket is already encrypted.
      final transport = ScriptedTransport([
        authMoreData([0x04]),
        okPacket(),
      ], isSecure: true);

      await run(transport);

      expect(transport.sent, hasLength(2));
      expect(transport.sent[1], nulTerminated('secret'));
    });

    test('does not ask for the public key', () async {
      // Requesting it would be a wasted round trip on every full auth.
      final transport = ScriptedTransport([
        authMoreData([0x04]),
        okPacket(),
      ], isSecure: true);

      await run(transport);

      expect(transport.sent[1], isNot([0x02]));
    });
  });

  group('caching_sha2_password, full auth over a plaintext socket', () {
    List<Uint8List> script() => [
      authMoreData([0x04]),
      authMoreData(utf8.encode(samplePublicKeyPem)),
      okPacket(),
    ];

    test('asks for the public key first', () async {
      final transport = ScriptedTransport(script());

      await run(transport);

      expect(transport.sent[1], [0x02]);
    });

    test('then sends a ciphertext of the key width', () async {
      final transport = ScriptedTransport(script());

      await run(transport);

      expect(transport.sent, hasLength(3));
      expect(transport.sent[2], hasLength(256));
    });

    test('never puts the password on the wire in the clear', () async {
      // The whole reason this path exists.
      final transport = ScriptedTransport(script());

      await run(transport);

      for (final packet in transport.sent) {
        expect(
          containsBytes(packet, utf8.encode('secret')),
          isFalse,
          reason: 'the password appears in a packet',
        );
      }
    });

    test(
      'a different ciphertext each time, because the seed is random',
      () async {
        final first = ScriptedTransport(script());
        final second = ScriptedTransport(script());

        await run(first);
        await run(second);

        expect(first.sent[2], isNot(second.sent[2]));
      },
    );

    test(
      'a public key that is not a key fails with something readable',
      () async {
        final transport = ScriptedTransport([
          authMoreData([0x04]),
          authMoreData(utf8.encode('not a key')),
          okPacket(),
        ]);

        expect(run(transport), throwsA(isA<MySqlProtocolException>()));
      },
    );
  });

  group('switching plugin', () {
    test('recomputes with the NEW scramble', () async {
      // The switch carries a fresh scramble. Reusing the handshake's is the
      // easiest mistake here and produces a token of exactly the right
      // length that the server refuses.
      final transport = ScriptedTransport([
        authSwitch('mysql_native_password', otherScramble),
        okPacket(),
      ]);

      await run(transport);

      expect(transport.sent, hasLength(2));
      expect(
        transport.sent[1],
        nativePasswordToken(password: 'secret', scramble: otherScramble),
      );
      expect(
        transport.sent[1],
        isNot(nativePasswordToken(password: 'secret', scramble: scramble)),
      );
    });

    test('sends the bare token, not another handshake response', () async {
      final transport = ScriptedTransport([
        authSwitch('mysql_native_password', otherScramble),
        okPacket(),
      ]);

      await run(transport);

      expect(transport.sent[1], hasLength(20));
    });

    test('a switch to caching_sha2 goes through its rounds too', () async {
      // Which is what happens when the server's default plugin is native
      // but the account uses caching_sha2.
      final transport = ScriptedTransport([
        authSwitch('caching_sha2_password', otherScramble),
        authMoreData([0x03]),
        okPacket(),
      ]);

      await run(transport, plugin: 'mysql_native_password');

      expect(transport.sent, hasLength(2));
      expect(
        transport.sent[1],
        cachingSha2FastAuthToken(password: 'secret', scramble: otherScramble),
      );
    });

    test('a switch then full auth uses the post-switch scramble', () async {
      // The switch-then-token and switch-then-fast-path cases are covered
      // separately. This one pins that the public-key branch also reaches
      // for the NEW scramble, since that is the branch where a stale one
      // would be hardest to notice.
      final transport = ScriptedTransport([
        authSwitch('caching_sha2_password', otherScramble),
        authMoreData([0x04]),
        authMoreData(utf8.encode(samplePublicKeyPem)),
        okPacket(),
      ]);

      await run(transport, plugin: 'mysql_native_password');

      expect(transport.sent, hasLength(4));
      expect(
        transport.sent[1],
        cachingSha2FastAuthToken(password: 'secret', scramble: otherScramble),
      );
      expect(transport.sent[2], [0x02]);
      expect(transport.sent[3], hasLength(256));
    });

    test('a plugin we do not support is named in the failure', () async {
      final transport = ScriptedTransport([
        authSwitch('sha256_password', otherScramble),
      ]);

      await expectLater(
        run(transport),
        throwsA(
          isA<UnsupportedAuthPlugin>().having(
            (e) => e.toString(),
            'toString',
            contains('sha256_password'),
          ),
        ),
      );
    });

    test('an unsupported initial plugin is named too', () async {
      // The server can be configured with it as the default, in which case
      // nothing is ever sent.
      final transport = ScriptedTransport([okPacket()]);

      await expectLater(
        run(transport, plugin: 'sha256_password'),
        throwsA(
          isA<UnsupportedAuthPlugin>().having(
            (e) => e.toString(),
            'toString',
            contains('sha256_password'),
          ),
        ),
      );
    });
  });

  group('failing', () {
    test('gives up rather than looping on switch after switch', () async {
      // A server that keeps asking for a different plugin must not spin
      // this exchange forever. Ten rounds is the cap; the eleventh packet
      // is deliberately absent, so if the cap were off by one the transport
      // would run dry and report its own StateError instead.
      final transport = ScriptedTransport([
        for (var i = 0; i < 10; i++)
          authSwitch('mysql_native_password', otherScramble),
      ]);

      await expectLater(run(transport), throwsA(isA<MySqlProtocolException>()));
    });

    test('an unexpected packet while waiting for the public key', () async {
      // The reply to the 0x02 request has to be more data carrying the PEM.
      // Anything else means the stream is out of step, and this is the one
      // place in the exchange where being out of step could mean sending a
      // password somewhere unintended.
      //
      // The message is asserted, not just the type. Weakening this guard
      // does not necessarily stop the exception: an empty or nonsense PEM
      // reaching parsePublicKeyPem throws the same type from there, so a
      // type-only check cannot tell the guard from its absence. "public
      // key" alone is not a safe match either -- parsePublicKeyPem's own
      // "not a PEM-encoded public key" message contains that exact phrase
      // too, so it would pass under the same weakened guard it is meant to
      // catch. "but received" names this guard's own condition (expected
      // one thing, got another) and does not appear in that other message.
      final transport = ScriptedTransport([
        authMoreData([0x04]),
        okPacket(),
      ]);

      await expectLater(
        run(transport),
        throwsA(
          isA<MySqlProtocolException>().having(
            (e) => e.toString(),
            'toString',
            contains('but received'),
          ),
        ),
      );
    });

    test('an ERR while waiting for the public key is still an ERR', () async {
      // Errors keep their classification wherever they arrive.
      final transport = ScriptedTransport([
        authMoreData([0x04]),
        errPacket(1045, 'Access denied'),
      ]);

      await expectLater(run(transport), throwsA(isA<MySqlAccessDenied>()));
    });

    test('an ERR becomes a classified exception', () async {
      await expectLater(
        run(ScriptedTransport([errPacket(1045, 'Access denied')])),
        throwsA(isA<MySqlAccessDenied>()),
      );
    });

    test('an ERR mid-exchange is thrown too, not swallowed', () async {
      await expectLater(
        run(
          ScriptedTransport([
            authMoreData([0x04]),
            errPacket(1045, 'Access denied'),
          ], isSecure: true),
        ),
        throwsA(isA<MySqlAccessDenied>()),
      );
    });

    test('an unknown auth more data marker is a protocol failure', () async {
      await expectLater(
        run(
          ScriptedTransport([
            authMoreData([0x09]),
          ]),
        ),
        throwsA(isA<MySqlProtocolException>()),
      );
    });

    test('an empty auth more data is a protocol failure', () async {
      await expectLater(
        run(ScriptedTransport([authMoreData(const [])])),
        throwsA(isA<MySqlProtocolException>()),
      );
    });
  });

  group('an account with no password', () {
    test('sends an auth response that is actually empty', () async {
      // Read the field rather than searching for its contents. Asking
      // whether the packet "contains" an empty token is a question with
      // only one answer.
      final transport = ScriptedTransport([okPacket()]);

      await run(transport, password: '');

      final reader = ByteReader(transport.sent.single);
      reader.skip(32);
      expect(reader.readNulTerminatedString(), 'test');
      expect(
        reader.readLengthEncodedString(),
        isEmpty,
        reason: 'the server reads a zero-length response as no password',
      );
      expect(transport.sent, hasLength(1));
    });
  });

  group('a database in the handshake', () {
    test('is carried in the first packet', () async {
      final transport = ScriptedTransport([okPacket()]);

      await run(transport, database: 'shop');

      expect(containsBytes(transport.sent.single, utf8.encode('shop')), isTrue);
    });
  });
}
