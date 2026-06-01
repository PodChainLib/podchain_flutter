// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Signer
// Performs ECDSA P-256 signing and verification using package:cryptography.
// Signature format: base64url-encoded IEEE P1363-style r || s bytes.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'key_manager.dart';
import 'payload_builder.dart';
import 'types.dart';

class Signer {
  final KeyManager _keyManager;
  final Ecdsa _algorithm = Ecdsa.p256(Sha256());

  Signer({required KeyManager keyManager}) : _keyManager = keyManager;

  Future<SignedDeliveryProof> sign(DeliveryPayload payload) async {
    final keyPair = await _keyManager.loadPrivateKey();

    final payloadBytes = PayloadBuilder.canonicalBytes(payload);

    final signature = await _algorithm.sign(
      payloadBytes,
      keyPair: keyPair,
    );

    final encodedSignature = base64Url.encode(signature.bytes).replaceAll('=', '');
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

      final signature = Signature(
        signatureBytes,
        publicKey: publicKey,
      );

      return _algorithm.verify(
        payloadBytes,
        signature: signature,
      );
    } catch (_) {
      return false;
    }
  }
}