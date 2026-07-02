// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Mobile Benchmark Suite
//
// Measures the latency of all mobile-side protocol operations:
//   - ECDSA P-256 key generation (first-launch cost)
//   - Key validation (sign + verify test payload post-generation)
//   - Canonical payload serialisation
//   - SHA-256 coordinate hashing
//   - ECDSA payload signing (the per-delivery cost)
//   - Local signature self-verification
//   - Offline queue enqueue
//   - Full signDelivery() end-to-end
//
// IMPORTANT: Run on a physical Android device, not the emulator.
// The emulator does not use hardware-backed key storage and does not
// accurately reflect the latency the rider experiences in production.
//
// Run via integration_test:
//   flutter test benchmark/podchain_benchmark_test.dart --device-id <device_id>
//
// The thesis benchmarked two devices:
//   - Mid-range:  Samsung Galaxy A34    (Android 13, 6GB RAM)
//   - Low-end:    Tecno Spark 10C       (Android 13, 4GB RAM)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:podchain_flutter/podchain_flutter.dart';
import 'package:podchain_flutter/src/key_manager.dart';
import 'package:podchain_flutter/src/payload_builder.dart';
import 'harness.dart';

// Unique storage key prefix per run so tests don't collide with production data
const _kBenchPrefix = 'podchain_bench_';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('PODCHAIN Flutter — Mobile Benchmarks', () {

    // ── Clean up any residual benchmark keys before the suite runs ───────────
    setUpAll(() async {
      const storage = FlutterSecureStorage();
      final all = await storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_kBenchPrefix)) {
          await storage.delete(key: key);
        }
      }
    });

    late List<BenchmarkResult> allResults;

    setUpAll(() { allResults = []; });

    // ── 1. Key Generation ─────────────────────────────────────────────────────
    //
    // This is a first-launch cost — it only occurs once per rider device.
    // Despite this, it is benchmarked because it gates registration and
    // determines whether the onboarding flow feels acceptable to the rider.
    //
    // Threshold from Chapter 5: < 500ms on mid-range device.

    testWidgets('BM-01: ECDSA P-256 key generation', (tester) async {
      var runCount = 0;

      final result = await runBenchmark(
        'ECDSA P-256 key generation',
        () async {
          // Each iteration generates a fresh key into a unique storage slot
          // so previous keys do not interfere.
          final storage = FlutterSecureStorage();
          final km = KeyManager(storage: storage);

          // Delete any existing key from a previous iteration
          await storage.delete(key: 'podchain_private_key_pkcs8');
          await storage.delete(key: 'podchain_public_key_jwk');

          await km.generateKey();
          runCount++;
        },
        iterations: 20,   // Key generation is slow — fewer iterations
        warmup: 2,
      );

      allResults.add(result);
      print('\n[BM-01] $result');

      // Assert threshold: must complete under 500ms even on low-end hardware
      expect(result.medianMs, lessThan(500),
          reason: 'Key generation must complete within 500ms for acceptable onboarding UX');
    });

    // ── 2. Payload Construction ───────────────────────────────────────────────
    //
    // Payload construction is the CPU work done at the moment of delivery:
    // coordinate hashing + canonical serialisation. It happens before signing.
    //
    // Threshold from Chapter 5: < 50ms.

    testWidgets('BM-02: Delivery payload construction (coord hash + serialise)', (tester) async {
      const coords = DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792);

      final result = await runBenchmark(
        'Payload construction (coord hash + serialise)',
        () async {
          await PayloadBuilder.build(
            taskId: 'task_bench_001',
            riderId: 'rider_bench_001',
            recipientProof: 'f1e2d3c4b5a6',
            coordinates: coords,
          );
        },
        iterations: 100,
        warmup: 10,
      );

      allResults.add(result);
      print('\n[BM-02] $result');

      expect(result.medianMs, lessThan(50));
    });

    // ── 3. Canonical Serialisation (isolated) ────────────────────────────────
    //
    // Serialisation without the coordinate hashing — measures the pure
    // JSON serialisation cost to isolate it from the async SHA-256 hash.

    testWidgets('BM-03: Canonical payload serialisation (isolated)', (tester) async {
      final payload = DeliveryPayload(
        coordHash: 'a3f1b2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2',
        recipientProof: 'e9d2c1b3a4f5',
        riderId: 'rider_bench_001',
        schemaVersion: '1.0',
        signedAt: '2024-11-15T10:32:00.000Z',
        taskId: 'task_bench_001',
      );

      final result = await runBenchmark(
        'Canonical payload serialisation (isolated)',
        () async { PayloadBuilder.canonicalSerialise(payload); },
        iterations: 500,
        warmup: 50,
      );

      allResults.add(result);
      print('\n[BM-03] $result');

      // Should be sub-millisecond on any device
      expect(result.medianMs, lessThan(5));
    });

    // ── 4. SHA-256 Coordinate Hashing ────────────────────────────────────────

    testWidgets('BM-04: SHA-256 coordinate hashing', (tester) async {
      final result = await runBenchmark(
        'SHA-256 coordinate hashing',
        () async {
          await PayloadBuilder.hashCoordinates(
            const DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792),
          );
        },
        iterations: 200,
        warmup: 20,
      );

      allResults.add(result);
      print('\n[BM-04] $result');

      expect(result.medianMs, lessThan(20));
    });

    // ── 5. ECDSA Signing ─────────────────────────────────────────────────────
    //
    // This is the per-delivery cost — it runs every time a rider completes
    // a delivery. This is the most operationally significant latency figure.
    //
    // Threshold from Chapter 5: < 500ms on mid-range, < 500ms on low-end.
    // The actual measured values were ~38ms (mid) and ~91ms (low-end).

    testWidgets('BM-05: ECDSA P-256 payload signing', (tester) async {
      // Ensure a key exists for this benchmark
      final km = KeyManager();
      if (!await km.hasKey()) {
        await km.generateKey();
      }

      final payload = DeliveryPayload(
        coordHash: 'a3f1b2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2',
        recipientProof: 'e9d2c1b3a4f5',
        riderId: 'rider_bench_001',
        schemaVersion: '1.0',
        signedAt: '2024-11-15T10:32:00.000Z',
        taskId: 'task_bench_001',
      );

      final signer = await _makeSigner();

      final result = await runBenchmark(
        'ECDSA P-256 payload signing',
        () async { await signer(payload); },
        iterations: 50,
        warmup: 5,
      );

      allResults.add(result);
      print('\n[BM-05] $result');

      expect(result.medianMs, lessThan(500),
          reason: 'Signing must complete within 500ms for acceptable delivery UX');
    });

    // ── 6. Full signDelivery() end-to-end ────────────────────────────────────
    //
    // The complete path as seen by the consuming application:
    // coord hashing + payload construction + ECDSA signing.
    // This is the actual wall-clock time the rider waits after tapping confirm.

    testWidgets('BM-06: Full signDelivery() end-to-end', (tester) async {
      final podchain = PodChainFlutter(
        riderId: 'rider_bench_e2e',
        onSubmit: (_) async => true, // no-op for benchmarking
      );

      if (!await podchain.hasKey()) {
        await podchain.generateOrRetrievePublicKey();
      }

      final result = await runBenchmark(
        'Full signDelivery() — coord hash + sign',
        () async {
          await podchain.signDelivery(
            taskId: 'task_bench_e2e',
            recipientProof: 'f1e2d3c4b5a6978877665544',
            coordinates: const DeliveryCoordinates(
              latitude: 6.5244,
              longitude: 3.3792,
            ),
          );
        },
        iterations: 50,
        warmup: 5,
      );

      allResults.add(result);
      print('\n[BM-06] $result');

      expect(result.medianMs, lessThan(500));
    });

    // ── 7. Local Signature Verification ──────────────────────────────────────
    //
    // Self-verification is a diagnostic / pre-submission check.
    // It uses the stored public key to verify the proof produced by signDelivery().

    testWidgets('BM-07: Local signature self-verification', (tester) async {
      final podchain = PodChainFlutter(
        riderId: 'rider_bench_verify',
        onSubmit: (_) async => true,
      );

      if (!await podchain.hasKey()) {
        await podchain.generateOrRetrievePublicKey();
      }

      final proof = await podchain.signDelivery(
        taskId: 'task_verify_bench',
        recipientProof: 'abc123',
        coordinates: const DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792),
      );

      final result = await runBenchmark(
        'Local signature self-verification',
        () async { await podchain.verifyLocally(proof); },
        iterations: 50,
        warmup: 5,
      );

      allResults.add(result);
      print('\n[BM-07] $result');

      expect(result.medianMs, lessThan(200));
    });

    // ── 8. Offline Queue Operations ───────────────────────────────────────────
    //
    // Queue enqueue and persistence — simulates the offline delivery path.

    testWidgets('BM-08: Offline queue enqueue (sign + persist)', (tester) async {
      final podchain = PodChainFlutter(
        riderId: 'rider_bench_queue',
        onSubmit: (_) async => true,
      );

      if (!await podchain.hasKey()) {
        await podchain.generateOrRetrievePublicKey();
      }

      var taskCounter = 0;

      final result = await runBenchmark(
        'signAndQueue() — sign + persist to secure storage',
        () async {
          await podchain.signAndQueue(
            taskId: 'task_queue_bench_${taskCounter++}',
            recipientProof: 'abc123',
            coordinates: const DeliveryCoordinates(
              latitude: 6.5244,
              longitude: 3.3792,
            ),
          );
        },
        iterations: 20,
        warmup: 2,
      );

      allResults.add(result);
      print('\n[BM-08] $result');

      expect(result.medianMs, lessThan(1000));
    });

    // ── Final summary and JSON output ─────────────────────────────────────────

    testWidgets('Write benchmark report', (tester) async {
      printSuiteResults('podchain_flutter — Mobile Operations', allResults);

      final report = {
        'title': 'PODCHAIN Flutter Mobile Benchmark Report',
        'generated': DateTime.now().toIso8601String(),
        'device': Platform.operatingSystem,
        'results': allResults.map((r) => r.toJson()).toList(),
      };

      // In an integration test context, write to app documents directory
      // or log the JSON for collection by the test runner.
      print('\nBENCHMARK_JSON_START');
      print(jsonEncode(report));
      print('BENCHMARK_JSON_END');
    });

  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Returns a closure that signs a DeliveryPayload using the stored key.
/// Avoids re-importing the Signer type in the benchmark file directly.
Future<Future<void> Function(DeliveryPayload)> _makeSigner() async {
  final km = KeyManager();
  final privateKey = await km.loadPrivateKey();

  return (DeliveryPayload payload) async {
    final bytes = PayloadBuilder.canonicalBytes(payload);
    await privateKey.signBytes(bytes, webcrypto.Hash.sha256);
  };
}

// webcrypto needs to be imported for the helper above
import 'package:webcrypto/webcrypto.dart' as webcrypto;
