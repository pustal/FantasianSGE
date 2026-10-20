import 'dart:convert';
import 'dart:typed_data';

import 'package:fantasian_sge/src/core/save_exception.dart';
import 'package:fantasian_sge/src/core/steam_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parses a hex string such as `00ff10` into bytes.
Uint8List hex(String value) => Uint8List.fromList(<int>[
  for (int i = 0; i < value.length; i += 2) int.parse(value.substring(i, i + 2), radix: 16),
]);

void main() {
  group('SteamCrypto', () {
    test('matches FIPS-197 appendix C.1 (single block, zero IV)', () {
      final SteamCrypto crypto = SteamCrypto.withKey(
        hex('000102030405060708090a0b0c0d0e0f'),
        Uint8List(16),
      );
      final Uint8List out = crypto.encryptBytes(hex('00112233445566778899aabbccddeeff'));
      // First block is the raw AES output; the second is the PKCS#7 padding.
      expect(out.sublist(0, 16), hex('69c4e0d86a7b0430d8cdb78070b4c55a'));
      expect(out.length, 32);
    });

    test('matches NIST SP 800-38A F.2.1 (CBC chaining)', () {
      final SteamCrypto crypto = SteamCrypto.withKey(
        hex('2b7e151628aed2a6abf7158809cf4f3c'),
        hex('000102030405060708090a0b0c0d0e0f'),
      );
      final Uint8List out = crypto.encryptBytes(
        hex('6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51'),
      );
      expect(out.sublist(0, 32),
          hex('7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2'));
    });

    test('round-trips text with the game key', () {
      final SteamCrypto crypto = SteamCrypto();
      const String text = '{"keys":["Date"],"values":["2026/10/20 16:38:00"]} ✨';
      final String encrypted = crypto.encryptRecord(text);
      expect(base64.decode(encrypted).length % 16, 0);
      expect(crypto.decryptRecord(encrypted), text);
    });

    test('rejects data that is not a whole number of blocks', () {
      expect(
        () => SteamCrypto().decryptRecord(base64.encode(<int>[1, 2, 3])),
        throwsA(isA<SaveException>()),
      );
    });
  });
}
