// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Type Definitions
// All domain types used across the podchain_flutter library.
// Must remain consistent with the TypeScript types in the server library.
// ─────────────────────────────────────────────────────────────────────────────

/// The tier of the RecipientToken scheme assigned to a delivery task.
enum RecipientTokenTier {
  /// Tier 1 — Passive Token. No recipient action required.
  passive,

  /// Tier 2 — OTP Token. Recipient shares a one-time code with the rider.
  otp,

  /// Tier 3 — Two-Sided Signing. Recipient signs via WebCrypto in their browser.
  twoSided,
}

/// The signed delivery payload constructed by the rider's application.
/// This is the exact structure that is canonically serialised and signed
/// with the rider's ECDSA private key.
///
/// Field order in the canonical serialisation is alphabetical — this
/// is enforced by [PayloadBuilder.canonicalSerialise] and must produce
/// byte-for-byte identical output to the server's canonicalSerialise().
class DeliveryPayload {
  final String coordHash;      // SHA-256 of "lat,lng" — never raw coordinates
  final String recipientProof; // Tier-appropriate token or confirmation
  final String riderId;
  final String schemaVersion;  // Always "1.0"
  final String signedAt;       // ISO 8601 UTC timestamp
  final String taskId;

  const DeliveryPayload({
    required this.coordHash,
    required this.recipientProof,
    required this.riderId,
    required this.schemaVersion,
    required this.signedAt,
    required this.taskId,
  });

  /// Returns the fields as a map with keys in alphabetical order.
  /// Used by the canonical serialiser.
  Map<String, String> toOrderedMap() => {
        'coordHash': coordHash,
        'recipientProof': recipientProof,
        'riderId': riderId,
        'schemaVersion': schemaVersion,
        'signedAt': signedAt,
        'taskId': taskId,
      };
}

/// The signed delivery proof ready for transmission to the platform API.
class SignedDeliveryProof {
  /// The canonical JSON string that was signed.
  final String payload;

  /// base64url IEEE P1363 ECDSA signature over the payload bytes.
  final String signature;

  /// The rider's identity as embedded in the payload.
  final String riderId;

  /// The task this proof is for.
  final String taskId;

  /// True if this proof was queued while offline and is awaiting submission.
  final bool isQueued;

  /// The time at which this proof was queued (if offline).
  final DateTime? queuedAt;

  const SignedDeliveryProof({
    required this.payload,
    required this.signature,
    required this.riderId,
    required this.taskId,
    this.isQueued = false,
    this.queuedAt,
  });

  Map<String, dynamic> toJson() => {
        'payload': payload,
        'signature': signature,
        'riderId': riderId,
        'taskId': taskId,
        'isQueued': isQueued,
        'queuedAt': queuedAt?.toIso8601String(),
      };

  factory SignedDeliveryProof.fromJson(Map<String, dynamic> json) =>
      SignedDeliveryProof(
        payload: json['payload'] as String,
        signature: json['signature'] as String,
        riderId: json['riderId'] as String,
        taskId: json['taskId'] as String,
        isQueued: json['isQueued'] as bool? ?? false,
        queuedAt: json['queuedAt'] != null
            ? DateTime.parse(json['queuedAt'] as String)
            : null,
      );
}

/// GPS coordinates at the time of signing.
class DeliveryCoordinates {
  final double latitude;
  final double longitude;

  const DeliveryCoordinates({
    required this.latitude,
    required this.longitude,
  });

  /// Returns the canonical string representation used for hashing.
  /// Format: "latitude,longitude" as decimal strings.
  String toHashInput() => '$latitude,$longitude';
}

/// Error types specific to the podchain_flutter library.
class PodChainFlutterError implements Exception {
  final String code;
  final String message;

  const PodChainFlutterError(this.code, this.message);

  @override
  String toString() => 'PodChainFlutterError[$code]: $message';
}
