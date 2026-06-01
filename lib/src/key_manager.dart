// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Key Manager
//
// Handles the full lifecycle of the rider's ECDSA P-256 signing identity:
// key generation, secure storage, export for platform registration, and
// retrieval for signing operations.
//
// Uses package:cryptography instead of package:webcrypto.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'types.dart';

const _kPrivateKeyStorageKey = 'podchain_private_key_p256_d';
const _kPublicKeyStorageKey = 'podchain_public_key_p256_xy';

class KeyManager {
  final FlutterSecureStorage _storage;
  final Ecdsa _algorithm = Ecdsa.p256(Sha256());

  KeyManager({FlutterSecureStorage? storage})
      : _storage = storage ??
      const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  // ── Key Generation ──────────────────────────────────────────────────────────

  /// Generates a new ECDSA P-256 key pair and stores it securely on the device.
  ///
  /// Returns the public key as a JSON Web Key map, ready to be transmitted
  /// to the platform's rider registration endpoint.
  Future<Map<String, dynamic>> generateKey() async {
    final existing = await _storage.read(key: _kPrivateKeyStorageKey);

    if (existing != null) {
      throw const PodChainFlutterError(
        'KEY_ALREADY_EXISTS',
        'A key already exists on this device. Revoke it before generating a new one.',
      );
    }

    final generatedKeyPair = await _algorithm.newKeyPair();
    final keyPair = await generatedKeyPair.extract();

    await _validateKey(keyPair);

    await _storage.write(
      key: _kPrivateKeyStorageKey,
      value: _base64UrlEncodeNoPadding(keyPair.d),
    );

    await _storage.write(
      key: _kPublicKeyStorageKey,
      value: jsonEncode({
        'x': _base64UrlEncodeNoPadding(keyPair.x),
        'y': _base64UrlEncodeNoPadding(keyPair.y),
      }),
    );

    return _publicKeyToJwk(keyPair.publicKey);
  }

  /// Returns true if a key pair is already stored on this device.
  Future<bool> hasKey() async {
    final stored = await _storage.read(key: _kPrivateKeyStorageKey);
    return stored != null;
  }

  /// Returns the stored public key JWK, or null if no key exists.
  Future<Map<String, dynamic>?> getPublicKeyJwk() async {
    final publicKey = await getPublicKey();
    if (publicKey == null) return null;

    return _publicKeyToJwk(publicKey);
  }

  /// Returns the stored public key, or null if no key exists.
  Future<EcPublicKey?> getPublicKey() async {
    final stored = await _storage.read(key: _kPublicKeyStorageKey);
    if (stored == null) return null;

    final publicKeyJson = jsonDecode(stored) as Map<String, dynamic>;

    return EcPublicKey(
      x: _base64UrlDecodeNoPadding(publicKeyJson['x'] as String),
      y: _base64UrlDecodeNoPadding(publicKeyJson['y'] as String),
      type: KeyPairType.p256,
    );
  }

  /// Returns the stored public key, generating one if none exists.
  Future<Map<String, dynamic>> generateOrRetrievePublicKey() async {
    if (await hasKey()) {
      final publicKeyJwk = await getPublicKeyJwk();

      if (publicKeyJwk == null) {
        throw const PodChainFlutterError(
          'PUBLIC_KEY_NOT_FOUND',
          'A private key exists but the public key is missing.',
        );
      }

      return publicKeyJwk;
    }

    return generateKey();
  }

  // ── Private Key Retrieval for Signing ───────────────────────────────────────

  /// Loads the stored private key as [EcKeyPairData] ready for signing.
  Future<EcKeyPairData> loadPrivateKey() async {
    final privateKeyStored = await _storage.read(key: _kPrivateKeyStorageKey);
    final publicKeyStored = await _storage.read(key: _kPublicKeyStorageKey);

    if (privateKeyStored == null || publicKeyStored == null) {
      throw const PodChainFlutterError(
        'KEY_NOT_FOUND',
        'No key found on this device. Call generateKey() first.',
      );
    }

    final publicKeyJson = jsonDecode(publicKeyStored) as Map<String, dynamic>;

    return EcKeyPairData(
      d: _base64UrlDecodeNoPadding(privateKeyStored),
      x: _base64UrlDecodeNoPadding(publicKeyJson['x'] as String),
      y: _base64UrlDecodeNoPadding(publicKeyJson['y'] as String),
      type: KeyPairType.p256,
    );
  }

  // ── Key Deletion ─────────────────────────────────────────────────────────────

  /// Deletes the stored key pair from secure storage.
  Future<void> deleteKey() async {
    await _storage.delete(key: _kPrivateKeyStorageKey);
    await _storage.delete(key: _kPublicKeyStorageKey);
  }

  // ── Key Validation ───────────────────────────────────────────────────────────

  Future<void> _validateKey(EcKeyPairData keyPair) async {
    const testData = 'PODCHAIN_KEY_VALIDATION_v1.0';
    final testBytes = Uint8List.fromList(utf8.encode(testData));

    final signature = await _algorithm.sign(
      testBytes,
      keyPair: keyPair,
    );

    final valid = await _algorithm.verify(
      testBytes,
      signature: signature,
    );

    if (!valid) {
      throw const PodChainFlutterError(
        'KEY_VALIDATION_FAILED',
        'Generated key pair failed the validation signing test.',
      );
    }
  }

  // ── Public Key Export ───────────────────────────────────────────────────────

  Map<String, dynamic> _publicKeyToJwk(EcPublicKey publicKey) {
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': _base64UrlEncodeNoPadding(publicKey.x),
      'y': _base64UrlEncodeNoPadding(publicKey.y),
      'ext': true,
      'key_ops': ['verify'],
    };
  }

  String _base64UrlEncodeNoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Uint8List _base64UrlDecodeNoPadding(String value) {
    final padded = value.padRight(
      value.length + (4 - value.length % 4) % 4,
      '=',
    );

    return Uint8List.fromList(base64Url.decode(padded));
  }
}