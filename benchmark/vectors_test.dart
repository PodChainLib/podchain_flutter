// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Cross-Platform Vector Tests (Dart / Mobile side)
//
// Validates canonical serialisation output against the same test vectors
// as the TypeScript server library. Both must produce byte-for-byte
// identical canonical strings and SHA-256 digests for the same input.
//
// Run: flutter test benchmark/vectors_test.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:webcrypto/webcrypto.dart';
import 'package:podchain_flutter/src/types.dart';
import 'package:podchain_flutter/src/payload_builder.dart';

// ── Shared test vectors — must match vectors.ts exactly ───────────────────────

class _Vector {
  final String description;
  final DeliveryPayload input;
  final String expectedCanonical;
  final String? expectedSha256; // null until pinned on first run

  const _Vector({
    required this.description,
    required this.input,
    required this.expectedCanonical,
    this.expectedSha256,
  });
}

final _vectors = [
  _Vector(
    description: 'Standard Tier 1 delivery payload',
    input: DeliveryPayload(
      coordHash:     'a3f1b2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2',
      recipientProof:'e9d2c1b3a4f5e6d7c8b9a0f1',
      riderId:       'rider_emeka_001',
      schemaVersion: '1.0',
      signedAt:      '2024-11-15T10:32:00.000Z',
      taskId:        'task_abc123def456',
    ),
    expectedCanonical:
      '{"coordHash":"a3f1b2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2",'
      '"recipientProof":"e9d2c1b3a4f5e6d7c8b9a0f1",'
      '"riderId":"rider_emeka_001",'
      '"schemaVersion":"1.0",'
      '"signedAt":"2024-11-15T10:32:00.000Z",'
      '"taskId":"task_abc123def456"}',
  ),
  _Vector(
    description: 'Minimal field values (edge case)',
    input: DeliveryPayload(
      coordHash:     '0' * 64,
      recipientProof:'x',
      riderId:       'r',
      schemaVersion: '1.0',
      signedAt:      '2024-01-01T00:00:00.000Z',
      taskId:        't',
    ),
    expectedCanonical:
      '{"coordHash":"${'0' * 64}",'
      '"recipientProof":"x",'
      '"riderId":"r",'
      '"schemaVersion":"1.0",'
      '"signedAt":"2024-01-01T00:00:00.000Z",'
      '"taskId":"t"}',
  ),
  _Vector(
    description: 'Tier 2 payload (numeric OTP as recipientProof)',
    input: DeliveryPayload(
      coordHash:     'b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3',
      recipientProof:'847291',
      riderId:       'rider_fatima_002',
      schemaVersion: '1.0',
      signedAt:      '2024-11-15T14:05:30.000Z',
      taskId:        'task_xyz789uvw012',
    ),
    expectedCanonical:
      '{"coordHash":"b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3",'
      '"recipientProof":"847291",'
      '"riderId":"rider_fatima_002",'
      '"schemaVersion":"1.0",'
      '"signedAt":"2024-11-15T14:05:30.000Z",'
      '"taskId":"task_xyz789uvw012"}',
  ),
];

// ── Helper: SHA-256 of a UTF-8 string as lowercase hex ───────────────────────

Future<String> _sha256Hex(String input) async {
  final bytes = Uint8List.fromList(utf8.encode(input));
  final digest = await Hash.sha256.digestBytes(bytes);
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Cross-platform serialisation vectors (Dart)', () {

    for (final vector in _vectors) {
      test('Vector: ${vector.description}', () async {
        final canonical = PayloadBuilder.canonicalSerialise(vector.input);

        // Must match the TypeScript expected output exactly
        expect(canonical, equals(vector.expectedCanonical),
            reason: 'Canonical serialisation must be byte-for-byte identical '
                'to the TypeScript server library output for this input');

        // Compute and log the SHA-256 for pinning
        final hash = await _sha256Hex(canonical);
        print('  [${vector.description}] SHA-256: $hash');

        if (vector.expectedSha256 != null) {
          expect(hash, equals(vector.expectedSha256));
        }
      });
    }

    test('No whitespace in any canonical output', () {
      for (final vector in _vectors) {
        final canonical = PayloadBuilder.canonicalSerialise(vector.input);
        expect(canonical.contains(' '), isFalse);
        expect(canonical.contains('\n'), isFalse);
        expect(canonical.contains('\t'), isFalse);
      }
    });

    test('Output is valid JSON with alphabetically ordered keys', () {
      for (final vector in _vectors) {
        final canonical = PayloadBuilder.canonicalSerialise(vector.input);
        final parsed = jsonDecode(canonical) as Map<String, dynamic>;
        final keys = parsed.keys.toList();
        final sorted = [...keys]..sort();
        expect(keys, equals(sorted),
            reason: 'Keys must appear in alphabetical order in the canonical output');
      }
    });

    test('Output round-trips to original values', () {
      for (final vector in _vectors) {
        final canonical = PayloadBuilder.canonicalSerialise(vector.input);
        final parsed = jsonDecode(canonical) as Map<String, dynamic>;

        expect(parsed['coordHash'],     equals(vector.input.coordHash));
        expect(parsed['recipientProof'],equals(vector.input.recipientProof));
        expect(parsed['riderId'],       equals(vector.input.riderId));
        expect(parsed['schemaVersion'], equals(vector.input.schemaVersion));
        expect(parsed['signedAt'],      equals(vector.input.signedAt));
        expect(parsed['taskId'],        equals(vector.input.taskId));
      }
    });

  });
}
