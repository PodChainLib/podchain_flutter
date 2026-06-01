// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Payload Builder
//
// Constructs the DeliveryPayload and produces its canonical serialisation
// for signing. The canonical format must be byte-for-byte identical to the
// output of the TypeScript canonicalSerialise() function on the server.
//
// Canonical format: UTF-8 JSON with keys sorted alphabetically A–Z,
// no whitespace (no spaces after colons or commas, no newlines).
// Any deviation will produce a signature mismatch on server verification.
// ─────────────────────────────────────────────────────────────────────────────

import 'types.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class PayloadBuilder {
  // ── Payload Construction ────────────────────────────────────────────────────

  /// Builds a [DeliveryPayload] from the delivery's components.
  ///
  /// [taskId]         The platform-assigned task identifier.
  /// [riderId]        The authenticated rider's identifier.
  /// [recipientProof] The RecipientToken value (tier-dependent).
  /// [coordinates]    The GPS coordinates at time of signing.
  ///
  /// The timestamp is set to the current UTC time at the moment this method
  /// is called — setting it on the device, not relying on a server clock,
  /// is required by the protocol specification.
  static Future<DeliveryPayload> build({
    required String taskId,
    required String riderId,
    required String recipientProof,
    required DeliveryCoordinates coordinates,
  }) async {
    final coordHash = await hashCoordinates(coordinates);

    return DeliveryPayload(
      coordHash: coordHash,
      recipientProof: recipientProof,
      riderId: riderId,
      schemaVersion: '1.0',
      signedAt: DateTime.now().toUtc().toIso8601String(),
      taskId: taskId,
    );
  }

  // ── Canonical Serialisation ─────────────────────────────────────────────────

  /// Produces the canonical JSON serialisation of a [DeliveryPayload].
  ///
  /// Keys are sorted alphabetically; no whitespace; UTF-8 encoding.
  /// This is the string that is signed by the rider's private key and
  /// verified by the server. Must be identical to the TypeScript
  /// canonicalSerialise() output for the same input.
  ///
  /// Shared test vectors validate this against the server implementation.
  static String canonicalSerialise(DeliveryPayload payload) {
    final map = payload.toOrderedMap();

    // Sort keys alphabetically — SplayTreeMap would also work but explicit
    // sorting makes the intent clear and is consistent with the TypeScript impl.
    final sortedKeys = map.keys.toList()..sort();
    final sortedMap = {for (final k in sortedKeys) k: map[k]};

    // jsonEncode produces compact JSON (no whitespace) by default in Dart.
    return jsonEncode(sortedMap);
  }

  /// Encodes the canonical serialisation as UTF-8 bytes for signing.
  static Uint8List canonicalBytes(DeliveryPayload payload) {
    return Uint8List.fromList(utf8.encode(canonicalSerialise(payload)));
  }

  // ── Coordinate Hashing ──────────────────────────────────────────────────────

  /// Computes SHA-256 of "lat,lng" and returns it as a lowercase hex string.
  ///
  /// Satisfies the NDPA 2023 data minimisation requirement: the raw GPS
  /// coordinates are hashed before being included in the signed payload,
  /// so they are never stored in plaintext in the Proof Certificate.
  static Future<String> hashCoordinates(DeliveryCoordinates coordinates) async {
    final input = coordinates.toHashInput();
    final digest = sha256.convert(utf8.encode(input));

    return digest.toString();
  }
}
