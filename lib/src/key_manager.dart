// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Key Manager
//
// Handles the full lifecycle of the rider's ECDSA P-256 signing identity:
// key generation, secure storage, export for platform registration, and
// retrieval for signing operations.
//
// SECURITY NOTE:
// Keys are generated using the webcrypto package, which delegates to
// BoringSSL (Android) and Apple Security Framework (iOS) — both of which
// use hardware-backed secure storage when available on the device.
// The private key is stored as PKCS8 bytes in flutter_secure_storage,
// which uses Android EncryptedSharedPreferences (AES-256-GCM, with the
// encryption key itself stored in Android Keystore) and iOS Keychain.
//
// This means the private key material is encrypted at rest and inaccessible
// to other applications — but unlike direct Android Keystore key generation,
// the raw key bytes are accessible in memory during signing operations.
// This is an honest tradeoff: it provides strong protection for most
// threat scenarios while maintaining cross-platform simplicity.
// A future version may use platform channels for direct Keystore signing.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webcrypto/webcrypto.dart';
import 'types.dart';

const _kPrivateKeyStorageKey = 'podchain_private_key_pkcs8';
const _kPublicKeyStorageKey = 'podchain_public_key_jwk';

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
  ///
  /// If a key already exists for this rider, throws [PodChainFlutterError]
  /// with code KEY_ALREADY_EXISTS. Use [hasKey] to check first, or
  /// [generateOrRetrievePublicKey] to get the existing public key if present.
  Future<Map<String, dynamic>> generateKey() async {
    final existing = await _storage.read(key: _kPrivateKeyStorageKey);
    if (existing != null) {
      throw const PodChainFlutterError(
        'KEY_ALREADY_EXISTS',
        'A key already exists on this device. Revoke it before generating a new one.',
      );
    }

    final keyPair = await EcdsaPrivateKey.generateKey(EllipticCurve.p256);

    // Validate the key works before storing — catches rare hardware keystore
    // compatibility issues on certain Android devices.
    await _validateKey((
      privateKey: keyPair.privateKey,
      publicKey: keyPair.publicKey,
    ));

    final pkcs8Bytes = await keyPair.privateKey.exportPkcs8Key();
    final publicKeyJwk = await keyPair.publicKey.exportJsonWebKey();

    await _storage.write(
      key: _kPrivateKeyStorageKey,
      value: base64Url.encode(pkcs8Bytes),
    );
    await _storage.write(
      key: _kPublicKeyStorageKey,
      value: jsonEncode(publicKeyJwk),
    );

    return publicKeyJwk;
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
    return jsonDecode(stored) as Map<String, dynamic>;
  }

  /// Returns the stored public key, generating one if none exists.
  /// Convenience method for the common onboarding flow.
  Future<Map<String, dynamic>> generateOrRetrievePublicKey() async {
    if (await hasKey()) {
      return (await getPublicKeyJwk())!;
    }
    return generateKey();
  }

  // ── Private Key Retrieval for Signing ───────────────────────────────────────

  /// Loads the stored private key as an [EcdsaPrivateKey] ready for signing.
  /// Throws [PodChainFlutterError] with code KEY_NOT_FOUND if no key exists.
  Future<EcdsaPrivateKey> loadPrivateKey() async {
    final stored = await _storage.read(key: _kPrivateKeyStorageKey);

    if (stored == null) {
      throw const PodChainFlutterError(
        'KEY_NOT_FOUND',
        'No key found on this device. Call generateKey() first.',
      );
    }

    final pkcs8Bytes = base64Url.decode(stored);
    return EcdsaPrivateKey.importPkcs8Key(pkcs8Bytes, EllipticCurve.p256);
  }

  // ── Key Deletion ─────────────────────────────────────────────────────────────

  /// Deletes the stored key pair from secure storage.
  /// Called when a rider is re-onboarding on a new device or after key revocation.
  Future<void> deleteKey() async {
    await _storage.delete(key: _kPrivateKeyStorageKey);
    await _storage.delete(key: _kPublicKeyStorageKey);
  }

  // ── Key Validation ───────────────────────────────────────────────────────────

  /// Validates a freshly generated key pair by signing and verifying a known
  /// test payload. Guards against rare hardware keystore compatibility issues
  /// on certain Android devices, as described in Chapter 4.4 of the thesis.
  Future<void> _validateKey(
      ({EcdsaPrivateKey privateKey, EcdsaPublicKey publicKey}) keyPair) async {
    const testData = 'PODCHAIN_KEY_VALIDATION_v1.0';
    final testBytes = Uint8List.fromList(utf8.encode(testData));

    final signature = await keyPair.privateKey.signBytes(testBytes, Hash.sha256);
    final valid =
        await keyPair.publicKey.verifyBytes(signature, testBytes, Hash.sha256);

    if (!valid) {
      throw const PodChainFlutterError(
        'KEY_VALIDATION_FAILED',
        'Generated key pair failed the validation signing test. '
            'The device may not support hardware-backed key generation.',
      );
    }
  }
}
