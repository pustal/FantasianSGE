/// AES-128-CBC with PKCS#7 padding, as FANTASIAN Neo Dimension uses for each
/// save record's `encryptedString` (which is then base64 encoded).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'constants.dart';
import 'save_exception.dart';

/// Encrypts and decrypts Neo Dimension save records.
///
/// The key and IV are constants baked into the game, so a single shared
/// instance is enough. The class is stateless: each call builds a fresh
/// cipher, because PointyCastle ciphers keep chaining state between calls.
final class SteamCrypto {
  /// Creates a codec that uses the game's own key and IV.
  SteamCrypto()
    : _key = Uint8List.fromList(utf8.encode(SteamConstants.aesKey)),
      _iv = Uint8List.fromList(utf8.encode(SteamConstants.aesIv));

  /// Creates a codec with an explicit 16-byte key and IV. Only used by tests
  /// that check the cipher against published NIST vectors.
  SteamCrypto.withKey(this._key, this._iv);

  final Uint8List _key;
  final Uint8List _iv;

  /// Encrypts [plaintext] (UTF-8 encoded) and returns the base64 text stored in
  /// a record's `encryptedString`.
  String encryptRecord(String plaintext) =>
      base64.encode(encryptBytes(Uint8List.fromList(utf8.encode(plaintext))));

  /// Reverses [encryptRecord]. Throws [SaveException] when the text is not
  /// valid base64 or does not decrypt with the game's key.
  String decryptRecord(String encoded) {
    final Uint8List raw;
    try {
      raw = base64.decode(encoded);
    } on FormatException {
      throw const SaveException('A Neo Dimension record is not valid base64.');
    }
    final Uint8List plain = decryptBytes(raw);
    try {
      return utf8.decode(plain);
    } on FormatException {
      throw const SaveException(
        'A Neo Dimension record decrypted to something that is not text.',
      );
    }
  }

  /// AES-128-CBC encryption with PKCS#7 padding.
  Uint8List encryptBytes(Uint8List data) => _cipher(forEncryption: true).process(data);

  /// AES-128-CBC decryption with PKCS#7 padding removal.
  Uint8List decryptBytes(Uint8List data) {
    if (data.isEmpty || data.length % 16 != 0) {
      throw const SaveException(
        'A Neo Dimension record is not a whole number of AES blocks.',
      );
    }
    try {
      return _cipher(forEncryption: false).process(data);
    } on ArgumentError {
      // PointyCastle reports bad padding as an ArgumentError.
      throw const SaveException(
        'A Neo Dimension record does not decrypt with the game key.',
        hint: 'This does not look like a FANTASIAN save.',
      );
    }
  }

  /// Builds a fresh padded CBC cipher in the requested direction.
  PaddedBlockCipher _cipher({required bool forEncryption}) {
    final PaddedBlockCipherImpl cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      forEncryption,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(_key), _iv),
        null,
      ),
    );
    return cipher;
  }
}
