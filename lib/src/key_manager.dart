// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Key Manager
//
// Handles the full lifecycle of the rider's ECDSA P-256 signing identity:
// key generation, secure storage, export for platform registration, and
// retrieval for signing operations.
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webcrypto/webcrypto.dart';

import 'types.dart';

const _kPrivateKeyStorageKey = 'podchain_private_key_p256_pkcs8';
const _kPublicKeyStorageKey = 'podchain_public_key_p256_jwk';

class KeyManager {
  final FlutterSecureStorage _storage;

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

    final generatedKeyPair = await _safeRun(
      () => EcdsaPrivateKey.generateKey(EllipticCurve.p256),
    );

    await _validateKey(generatedKeyPair.privateKey, generatedKeyPair.publicKey);

    final pkcs8 = await _safeRun(
      () => generatedKeyPair.privateKey.exportPkcs8Key(),
    );
    final publicJwk = _normalisePublicJwk(
      await _safeRun(
        () => generatedKeyPair.publicKey.exportJsonWebKey(),
      ),
    );

    await _storage.write(
      key: _kPrivateKeyStorageKey,
      value: _base64UrlEncodeNoPadding(pkcs8),
    );

    await _storage.write(
      key: _kPublicKeyStorageKey,
      value: jsonEncode(publicJwk),
    );

    return publicJwk;
  }

  /// Returns true if a key pair is already stored on this device.
  Future<bool> hasKey() async {
    final stored = await _storage.read(key: _kPrivateKeyStorageKey);
    return stored != null;
  }

  /// Returns the stored public key JWK, or null if no key exists.
  Future<Map<String, dynamic>?> getPublicKeyJwk() async {
    final stored = await _storage.read(key: _kPublicKeyStorageKey);
    if (stored == null) return null;

    return _normalisePublicJwk(jsonDecode(stored) as Map<String, dynamic>);
  }

  /// Returns the stored public key, or null if no key exists.
  Future<EcdsaPublicKey?> getPublicKey() async {
    final stored = await _storage.read(key: _kPublicKeyStorageKey);
    if (stored == null) return null;

    final publicKeyJson = jsonDecode(stored) as Map<String, dynamic>;

    return _safeRun(
      () => EcdsaPublicKey.importJsonWebKey(
        _normalisePublicJwk(publicKeyJson),
        EllipticCurve.p256,
      ),
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

  /// Loads the stored PKCS8 private key ready for signing.
  Future<EcdsaPrivateKey> loadPrivateKey() async {
    final privateKeyStored = await _storage.read(key: _kPrivateKeyStorageKey);
    final publicKeyStored = await _storage.read(key: _kPublicKeyStorageKey);

    if (privateKeyStored == null || publicKeyStored == null) {
      throw const PodChainFlutterError(
        'KEY_NOT_FOUND',
        'No key found on this device. Call generateKey() first.',
      );
    }

    return _safeRun(
      () => EcdsaPrivateKey.importPkcs8Key(
        _base64UrlDecodeNoPadding(privateKeyStored),
        EllipticCurve.p256,
      ),
    );
  }

  // ── Key Deletion ─────────────────────────────────────────────────────────────

  /// Deletes the stored key pair from secure storage.
  Future<void> deleteKey() async {
    await _storage.delete(key: _kPrivateKeyStorageKey);
    await _storage.delete(key: _kPublicKeyStorageKey);
  }

  // ── Key Validation ───────────────────────────────────────────────────────────

  Future<void> _validateKey(
    EcdsaPrivateKey privateKey,
    EcdsaPublicKey publicKey,
  ) async {
    const testData = 'PODCHAIN_KEY_VALIDATION_v1.0';
    final testBytes = Uint8List.fromList(utf8.encode(testData));

    final signature = await _safeRun(
      () => privateKey.signBytes(
        testBytes,
        Hash.sha256,
      ),
    );

    final valid = await _safeRun(
      () => publicKey.verifyBytes(
        signature,
        testBytes,
        Hash.sha256,
      ),
    );

    if (!valid) {
      throw const PodChainFlutterError(
        'KEY_VALIDATION_FAILED',
        'Generated key pair failed the validation signing test.',
      );
    }
  }

  Future<T> _safeRun<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on UnimplementedError {
      throw const PodChainFlutterError(
        'CRYPTO_BACKEND_UNAVAILABLE',
        'ECDSA WebCrypto backend unavailable on this platform/runtime.',
      );
    } on UnsupportedError {
      throw const PodChainFlutterError(
        'CRYPTO_BACKEND_UNAVAILABLE',
        'ECDSA WebCrypto backend unavailable on this platform/runtime.',
      );
    }
  }

  // ── Public Key Export ───────────────────────────────────────────────────────

  Map<String, dynamic> _normalisePublicJwk(Map<String, dynamic> jwk) {
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': jwk['x'] as String,
      'y': jwk['y'] as String,
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
