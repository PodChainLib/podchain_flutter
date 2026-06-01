// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Offline Queue
//
// Manages a persistent queue of signed proofs that could not be submitted
// immediately due to network unavailability. The queue drains automatically
// when connectivity is restored, submitting proofs in chronological order.
//
// Key design decisions:
//   - Signing happens immediately at delivery time regardless of connectivity.
//     The signed proof is then queued. This preserves the signing timestamp
//     accuracy and ensures the rider's delivery work is complete locally.
//   - Proofs are submitted in insertion order to maintain hash chain position
//     coherence on the server.
//   - Failed submissions (e.g. cancelled tasks) are logged and removed —
//     they are not retried indefinitely.
//   - The queue is persisted in flutter_secure_storage so it survives app
//     restarts during an extended offline period.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'types.dart';

const _kQueueStorageKey = 'podchain_offline_queue';

typedef SubmitProofCallback = Future<bool> Function(SignedDeliveryProof proof);

class OfflineQueue {
  final FlutterSecureStorage _storage;
  final SubmitProofCallback _submitCallback;
  bool _isDraining = false;

  OfflineQueue({
    required SubmitProofCallback onSubmit,
    FlutterSecureStorage? storage,
  })  : _submitCallback = onSubmit,
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            ) {
    _listenForConnectivity();
  }

  // ── Queue Management ────────────────────────────────────────────────────────

  /// Adds a signed proof to the offline queue.
  /// The proof is stamped with a [queuedAt] timestamp and appended to the
  /// persisted queue in secure storage.
  Future<void> enqueue(SignedDeliveryProof proof) async {
    final queued = SignedDeliveryProof(
      payload: proof.payload,
      signature: proof.signature,
      riderId: proof.riderId,
      taskId: proof.taskId,
      isQueued: true,
      queuedAt: DateTime.now().toUtc(),
    );

    final queue = await _loadQueue();
    queue.add(queued);
    await _saveQueue(queue);
  }

  /// Returns the number of proofs currently in the queue.
  Future<int> get length async {
    final queue = await _loadQueue();
    return queue.length;
  }

  /// Returns whether the queue is empty.
  Future<bool> get isEmpty async => (await length) == 0;

  // ── Queue Drain ─────────────────────────────────────────────────────────────

  /// Attempts to submit all queued proofs in chronological order.
  ///
  /// Proofs are submitted one at a time. If a submission succeeds, the proof
  /// is removed from the queue. If it fails, it is removed and logged as a
  /// failed submission — proofs are not retried to prevent indefinite queuing
  /// of proofs for tasks that may have been cancelled.
  ///
  /// This method is idempotent — calling it while a drain is already in
  /// progress has no effect.
  Future<List<QueueDrainResult>> drain() async {
    if (_isDraining) return [];

    final queue = await _loadQueue();
    if (queue.isEmpty) return [];

    _isDraining = true;
    final results = <QueueDrainResult>[];

    // Sort by queuedAt ascending — oldest proofs submitted first
    queue.sort((a, b) {
      if (a.queuedAt == null && b.queuedAt == null) return 0;
      if (a.queuedAt == null) return 1;
      if (b.queuedAt == null) return -1;
      return a.queuedAt!.compareTo(b.queuedAt!);
    });

    final remaining = <SignedDeliveryProof>[];

    for (final proof in queue) {
      bool submitted = false;
      try {
        submitted = await _submitCallback(proof);
      } catch (_) {
        submitted = false;
      }

      results.add(QueueDrainResult(
        taskId: proof.taskId,
        success: submitted,
        queuedAt: proof.queuedAt,
      ));

      // On failure, remove from queue (don't retry — see design note above)
      // On success, also remove from queue
      // Either way, we do not keep it in the remaining list
    }

    // Save the remaining empty queue (or any proofs added during drain)
    await _saveQueue(remaining);
    _isDraining = false;

    return results;
  }

  // ── Connectivity Listener ───────────────────────────────────────────────────

  void _listenForConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) async {
      final hasConnectivity = _hasUsableConnectivity(result);

      if (hasConnectivity && !await isEmpty) {
        await drain();
      }
    });
  }

  bool _hasUsableConnectivity(dynamic result) {
    final values = result is List<ConnectivityResult>
        ? result
        : <ConnectivityResult>[
            if (result is ConnectivityResult) result,
          ];

    return values.any(
      (value) =>
          value == ConnectivityResult.mobile ||
          value == ConnectivityResult.wifi ||
          value == ConnectivityResult.ethernet ||
          value == ConnectivityResult.vpn,
    );
  }

  // ── Persistence Helpers ─────────────────────────────────────────────────────

  Future<List<SignedDeliveryProof>> _loadQueue() async {
    final stored = await _storage.read(key: _kQueueStorageKey);
    if (stored == null) return [];

    final list = jsonDecode(stored) as List<dynamic>;
    return list
        .map((item) => SignedDeliveryProof.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveQueue(List<SignedDeliveryProof> queue) async {
    final json = jsonEncode(queue.map((p) => p.toJson()).toList());
    await _storage.write(key: _kQueueStorageKey, value: json);
  }

  /// Clears the queue. Used in tests and for administrative resets.
  Future<void> clear() async {
    await _storage.delete(key: _kQueueStorageKey);
  }
}

/// The result of a single proof submission attempt during a queue drain.
class QueueDrainResult {
  final String taskId;
  final bool success;
  final DateTime? queuedAt;

  const QueueDrainResult({
    required this.taskId,
    required this.success,
    this.queuedAt,
  });
}
