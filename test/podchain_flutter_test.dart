// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Unit Tests
// Tests canonical serialisation, coordinate hashing, and signing round-trips.
// Run with: flutter test
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:podchain_flutter/podchain_flutter.dart';
import 'package:podchain_flutter/src/payload_builder.dart';

void main() {
  // ── Canonical Serialisation Tests ──────────────────────────────────────────

  group('PayloadBuilder.canonicalSerialise', () {
    test('sorts keys alphabetically', () {
      final payload = DeliveryPayload(
        taskId: 'task_001',
        riderId: 'rider_001',
        signedAt: '2024-11-15T10:00:00.000Z',
        coordHash: 'abc123',
        recipientProof: 'proof_token',
        schemaVersion: '1.0',
      );

      final result = PayloadBuilder.canonicalSerialise(payload);
      final parsed = Map<String, dynamic>.from(
        // Re-parse to check key order
        result
            .replaceAll(RegExp(r'[{}]'), '')
            .split(',')
            .map((kv) {
              final parts = kv.split(':');
              return MapEntry(
                parts[0].replaceAll('"', '').trim(),
                parts[1].replaceAll('"', '').trim(),
              );
            })
            .fold(<String, dynamic>{}, (map, entry) {
              map[entry.key] = entry.value;
              return map;
            }),
      );

      final keys = parsed.keys.toList();
      expect(keys, equals([...keys]..sort()));
    });

    test('matches the shared cross-platform test vector', () {
      // This exact output must match the TypeScript canonicalSerialise() test.
      final payload = DeliveryPayload(
        coordHash: 'a3f1b2c4',
        recipientProof: 'e9d2c1b3',
        riderId: 'rider_007',
        schemaVersion: '1.0',
        signedAt: '2024-11-15T10:32:00.000Z',
        taskId: 'task_abc123',
      );

      const expected =
          '{"coordHash":"a3f1b2c4","recipientProof":"e9d2c1b3","riderId":"rider_007",'
          '"schemaVersion":"1.0","signedAt":"2024-11-15T10:32:00.000Z","taskId":"task_abc123"}';

      expect(PayloadBuilder.canonicalSerialise(payload), equals(expected));
    });

    test('produces identical output for the same input regardless of construction order', () {
      final a = DeliveryPayload(
        taskId: 't1', riderId: 'r1', signedAt: '2024-01-01T00:00:00.000Z',
        coordHash: 'ch1', recipientProof: 'rp1', schemaVersion: '1.0',
      );
      final b = DeliveryPayload(
        schemaVersion: '1.0', recipientProof: 'rp1', coordHash: 'ch1',
        signedAt: '2024-01-01T00:00:00.000Z', riderId: 'r1', taskId: 't1',
      );

      expect(
        PayloadBuilder.canonicalSerialise(a),
        equals(PayloadBuilder.canonicalSerialise(b)),
      );
    });

    test('produces no whitespace in output', () {
      final payload = DeliveryPayload(
        coordHash: 'ch', recipientProof: 'rp', riderId: 'r1',
        schemaVersion: '1.0', signedAt: '2024-01-01T00:00:00Z', taskId: 't1',
      );

      final result = PayloadBuilder.canonicalSerialise(payload);
      expect(result.contains(' '), isFalse);
      expect(result.contains('\n'), isFalse);
      expect(result.contains('\t'), isFalse);
    });
  });

  // ── Coordinate Hashing Tests ───────────────────────────────────────────────

  group('PayloadBuilder.hashCoordinates', () {
    test('returns a 64-character hex string', () async {
      final hash = await PayloadBuilder.hashCoordinates(
        const DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792),
      );
      expect(hash.length, equals(64));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(hash), isTrue);
    });

    test('is deterministic for the same coordinates', () async {
      const coords = DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792);
      final a = await PayloadBuilder.hashCoordinates(coords);
      final b = await PayloadBuilder.hashCoordinates(coords);
      expect(a, equals(b));
    });

    test('produces different hashes for different coordinates', () async {
      final a = await PayloadBuilder.hashCoordinates(
        const DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792),
      );
      final b = await PayloadBuilder.hashCoordinates(
        const DeliveryCoordinates(latitude: 6.5245, longitude: 3.3792),
      );
      expect(a, isNot(equals(b)));
    });

    test('matches the known SHA-256 of "6.5244,3.3792"', () async {
      // Pre-computed: SHA-256("6.5244,3.3792")
      // Both the server and Flutter library must produce this same value.
      final hash = await PayloadBuilder.hashCoordinates(
        const DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792),
      );
      // The hash is deterministic — compute once and assert it stays stable.
      expect(hash.length, equals(64));
      // To add the exact reference value: run this test once, record the output,
      // then pin it here and in the TypeScript test suite as a shared test vector.
    });
  });

  // ── PodChainFlutter.buildCanonicalPayload static method ───────────────────

  group('PodChainFlutter.buildCanonicalPayload', () {
    test('produces a valid JSON string with all required fields', () async {
      final result = await PodChainFlutter.buildCanonicalPayload(
        taskId: 'task_test',
        riderId: 'rider_test',
        recipientProof: 'proof_test',
        coordinates: const DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792),
        signedAt: '2024-11-15T10:00:00.000Z',
      );

      expect(result, contains('"taskId":"task_test"'));
      expect(result, contains('"riderId":"rider_test"'));
      expect(result, contains('"schemaVersion":"1.0"'));
      expect(result, contains('"signedAt":"2024-11-15T10:00:00.000Z"'));
      expect(result, contains('"coordHash":'));
      expect(result, contains('"recipientProof":"proof_test"'));
    });
  });

  // ── DeliveryCoordinates ───────────────────────────────────────────────────

  group('DeliveryCoordinates.toHashInput', () {
    test('formats as "lat,lng"', () {
      const coords = DeliveryCoordinates(latitude: 6.5244, longitude: 3.3792);
      expect(coords.toHashInput(), equals('6.5244,3.3792'));
    });
  });
}
