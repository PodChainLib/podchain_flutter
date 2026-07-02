// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Signer
// Performs ECDSA P-256 signing and verification using package:cryptography.
// Signature format: base64url-encoded IEEE P1363-style r || s bytes.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

import 'key_manager.dart';
import 'payload_builder.dart';
import 'types.dart';

class Signer {
  final KeyManager _keyManager;

  Signer({required KeyManager keyManager}) : _keyManager = keyManager;

  Future<SignedDeliveryProof> sign(DeliveryPayload payload) async {
    final keyPair = await _keyManager.loadPrivateKey();

    final payloadBytes = PayloadBuilder.canonicalBytes(payload);

    final signatureBytes = await _safeRun(
      () => keyPair.signBytes(
        payloadBytes,
        Hash.sha256,
      ),
    );

    final encodedSignature = base64Url.encode(signatureBytes).replaceAll('=', '');
    final canonicalPayload = PayloadBuilder.canonicalSerialise(payload);

    return SignedDeliveryProof(
      payload: canonicalPayload,
      signature: encodedSignature,
      riderId: payload.riderId,
      taskId: payload.taskId,
    );
  }

  Future<bool> verify(SignedDeliveryProof proof) async {
    final publicKey = await _keyManager.getPublicKey();

    if (publicKey == null) return false;

    try {
      final signatureBytes = base64Url.decode(
        proof.signature.padRight(
          proof.signature.length + (4 - proof.signature.length % 4) % 4,
          '=',
        ),
      );

      final payloadBytes = Uint8List.fromList(utf8.encode(proof.payload));

      return _safeRun(
        () => publicKey.verifyBytes(
          signatureBytes,
          payloadBytes,
          Hash.sha256,
        ),
      );
    } catch (_) {
      return false;
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
}
