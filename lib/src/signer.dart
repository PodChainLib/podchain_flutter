// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Signer
//
// Performs the ECDSA P-256 signing operation at the heart of the protocol.
// Uses the webcrypto package which delegates to BoringSSL (Android) and
// Apple Security Framework (iOS).
//
// Output format: base64url-encoded IEEE P1363 signature (r || s, 64 bytes
// for P-256). This matches the format produced by the browser's WebCrypto
// API (used in Tier 3 recipient signing) and consumed by Bun's crypto.subtle
// on the server.
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

  // ── Core Signing Operation ──────────────────────────────────────────────────

  /// Signs a [DeliveryPayload] using the rider's stored private key.
  ///
  /// Returns a [SignedDeliveryProof] containing:
  ///   - [SignedDeliveryProof.payload]    the canonical JSON string
  ///   - [SignedDeliveryProof.signature]  base64url IEEE P1363 ECDSA signature
  ///
  /// Signing is a local, offline operation — no network connectivity required.
  /// This is by design: the rider signs at the point of delivery, and the
  /// signed proof can be submitted later when connectivity is available.
  Future<SignedDeliveryProof> sign(DeliveryPayload payload) async {
    final privateKey = await _keyManager.loadPrivateKey();

    final payloadBytes = PayloadBuilder.canonicalBytes(payload);
    final signatureBytes = await privateKey.signBytes(payloadBytes, Hash.sha256);

    // Encode as base64url without padding — matches Bun's toBase64Url() output
    final signature = base64Url.encode(signatureBytes).replaceAll('=', '');
    final canonicalPayload = PayloadBuilder.canonicalSerialise(payload);

    return SignedDeliveryProof(
      payload: canonicalPayload,
      signature: signature,
      riderId: payload.riderId,
      taskId: payload.taskId,
    );
  }

  // ── Self-Verification ───────────────────────────────────────────────────────

  /// Verifies a signed proof against the stored public key.
  ///
  /// Primarily useful for integration testing — the authoritative verification
  /// is performed server-side by the podchain library. This method allows
  /// the mobile app to confirm a proof is well-formed before transmitting it.
  Future<bool> verify(SignedDeliveryProof proof) async {
    final publicKeyJwk = await _keyManager.getPublicKeyJwk();
    if (publicKeyJwk == null) return false;

    try {
      final publicKey = await EcdsaPublicKey.importJsonWebKey(
        publicKeyJwk,
        EllipticCurve.p256,
      );

      final sigBytes = base64Url.decode(
        proof.signature.padRight(
          proof.signature.length + (4 - proof.signature.length % 4) % 4,
          '=',
        ),
      );

      final payloadBytes = Uint8List.fromList(utf8.encode(proof.payload));

      return publicKey.verifyBytes(sigBytes, payloadBytes, Hash.sha256);
    } catch (_) {
      return false;
    }
  }
}
