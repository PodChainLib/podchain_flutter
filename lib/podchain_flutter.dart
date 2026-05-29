// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — PodChainFlutter Facade
//
// The single entry point for all mobile-side protocol operations.
// The consuming application interacts only with this class — all internal
// modules (KeyManager, PayloadBuilder, Signer, OfflineQueue) are hidden.
//
// Usage:
//   final podchain = PodChainFlutter(riderId: 'rider_007');
//
//   // On first launch — generate key and register with platform
//   final publicKey = await podchain.generateOrRetrievePublicKey();
//   await platformApi.registerKey(riderId: 'rider_007', publicKey: publicKey);
//
//   // At delivery point — sign and submit (or queue if offline)
//   final proof = await podchain.signDelivery(
//     taskId: 'task_abc',
//     recipientProof: otpCode,
//     coordinates: DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792),
//   );
//   await platformApi.submitProof(taskId: proof.taskId, proof: proof);
//
//   // Or — when offline:
//   await podchain.signAndQueue(
//     taskId: 'task_xyz',
//     recipientProof: passiveToken,
//     coordinates: currentLocation,
//   );
//   // Queue drains automatically when connectivity restores.
// ─────────────────────────────────────────────────────────────────────────────

library podchain_flutter;

export 'src/types.dart';

import 'src/key_manager.dart';
import 'src/payload_builder.dart';
import 'src/signer.dart';
import 'src/offline_queue.dart';
import 'src/types.dart';

class PodChainFlutter {
  final String riderId;

  late final KeyManager _keyManager;
  late final Signer _signer;
  late final OfflineQueue _offlineQueue;

  /// Creates a PodChainFlutter instance for the given rider.
  ///
  /// [onSubmit] is the callback used by the offline queue to submit proofs
  /// when connectivity is restored. It should call the platform API's
  /// POST /tasks/:id/complete endpoint and return true on success.
  PodChainFlutter({
    required this.riderId,
    required SubmitProofCallback onSubmit,
  }) {
    _keyManager = KeyManager();
    _signer = Signer(keyManager: _keyManager);
    _offlineQueue = OfflineQueue(onSubmit: onSubmit);
  }

  // ── Key Management ──────────────────────────────────────────────────────────

  /// Returns the rider's P-256 public key as a JWK map.
  ///
  /// Generates a new key pair if none exists on this device.
  /// If a key already exists, returns the existing public key.
  ///
  /// The returned map should be transmitted to the platform's rider
  /// registration endpoint (POST /riders/register) exactly once.
  Future<Map<String, dynamic>> generateOrRetrievePublicKey() async {
    return _keyManager.generateOrRetrievePublicKey();
  }

  /// Returns true if a key pair already exists on this device.
  Future<bool> hasKey() => _keyManager.hasKey();

  /// Deletes the key pair from secure storage.
  /// Call this when a rider is re-onboarding on a new device,
  /// after the old key has been revoked on the platform.
  Future<void> deleteKey() => _keyManager.deleteKey();

  // ── Signing ─────────────────────────────────────────────────────────────────

  /// Constructs and signs a delivery proof.
  ///
  /// [taskId]         The platform-assigned task identifier.
  /// [recipientProof] The RecipientToken value (tier-dependent):
  ///                  - Tier 1: the raw passive token from the task record
  ///                  - Tier 2: the OTP code obtained from the recipient
  ///                  - Tier 3: the full Tier3 confirmation JSON string
  /// [coordinates]    The device's GPS coordinates at the moment of signing.
  ///
  /// Returns a [SignedDeliveryProof] ready for submission to the platform.
  /// This operation is fully offline — no network connectivity required.
  Future<SignedDeliveryProof> signDelivery({
    required String taskId,
    required String recipientProof,
    required DeliveryCoordinates coordinates,
  }) async {
    final payload = await PayloadBuilder.build(
      taskId: taskId,
      riderId: riderId,
      recipientProof: recipientProof,
      coordinates: coordinates,
    );

    return _signer.sign(payload);
  }

  /// Signs a delivery proof and enqueues it for later submission.
  ///
  /// Use this when network connectivity is unavailable at delivery time.
  /// The queue drains automatically when connectivity is restored.
  /// Queued proofs include an [offlineSubmitted] flag that is preserved
  /// in the Proof Certificate on the server.
  Future<SignedDeliveryProof> signAndQueue({
    required String taskId,
    required String recipientProof,
    required DeliveryCoordinates coordinates,
  }) async {
    final proof = await signDelivery(
      taskId: taskId,
      recipientProof: recipientProof,
      coordinates: coordinates,
    );

    await _offlineQueue.enqueue(proof);
    return proof;
  }

  // ── Queue Management ────────────────────────────────────────────────────────

  /// Returns the number of proofs currently waiting in the offline queue.
  Future<int> get queueLength => _offlineQueue.length;

  /// Manually triggers a queue drain attempt.
  /// The queue also drains automatically on connectivity change events.
  Future<List<QueueDrainResult>> drainQueue() => _offlineQueue.drain();

  // ── Self-Verification (testing / diagnostics) ────────────────────────────────

  /// Verifies a signed proof against the locally stored public key.
  /// Useful for integration tests and pre-submission validation.
  Future<bool> verifyLocally(SignedDeliveryProof proof) => _signer.verify(proof);

  // ── Canonical Serialisation (exposed for testing) ────────────────────────────

  /// Returns the canonical JSON string for a given set of delivery parameters.
  /// Exposed primarily for cross-platform test vector validation.
  static Future<String> buildCanonicalPayload({
    required String taskId,
    required String riderId,
    required String recipientProof,
    required DeliveryCoordinates coordinates,
    required String signedAt,
  }) async {
    final coordHash = await PayloadBuilder.hashCoordinates(coordinates);
    final payload = DeliveryPayload(
      coordHash: coordHash,
      recipientProof: recipientProof,
      riderId: riderId,
      schemaVersion: '1.0',
      signedAt: signedAt,
      taskId: taskId,
    );
    return PayloadBuilder.canonicalSerialise(payload);
  }
}
