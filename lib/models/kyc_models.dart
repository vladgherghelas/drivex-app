import 'dart:typed_data';

// lib/models/kyc_models.dart
// Extension point: when integrating Onfido/Jumio, add sessionId + vendorPayload fields here.

class OcrResult {
  final String? name;
  final String? dateOfBirth;
  final String? expiryDate;
  final String? documentNumber;
  final String rawText;

  OcrResult({
    this.name,
    this.dateOfBirth,
    this.expiryDate,
    this.documentNumber,
    required this.rawText,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'dateOfBirth': dateOfBirth,
    'expiryDate': expiryDate,
    'documentNumber': documentNumber,
  };
}

class KycCapture {
  final String imagePath;        // blob URL on web, file path on native
  final Uint8List? imageBytes;   // always populated — use for Image.memory()
  final DateTime capturedAt;
  final String documentSide;    // 'front' | 'back'
  final String documentType;    // 'license' | 'passport' | 'national_id'
  final OcrResult? ocrResult;
  final Map<String, dynamic>? metadata;

  KycCapture({
    required this.imagePath,
    this.imageBytes,
    required this.capturedAt,
    required this.documentSide,
    required this.documentType,
    this.ocrResult,
    this.metadata,
  });
}

enum LivenessChallenge { lookForward, blink, smile, turnLeft, turnRight }

extension LivenessChallengeX on LivenessChallenge {
  String get instruction {
    switch (this) {
      case LivenessChallenge.lookForward: return 'Look straight at the camera';
      case LivenessChallenge.blink:       return 'Blink slowly';
      case LivenessChallenge.smile:       return 'Give a natural smile';
      case LivenessChallenge.turnLeft:    return 'Slowly turn your head left';
      case LivenessChallenge.turnRight:   return 'Slowly turn your head right';
    }
  }

  String get icon {
    switch (this) {
      case LivenessChallenge.lookForward: return '👁';
      case LivenessChallenge.blink:       return '😑';
      case LivenessChallenge.smile:       return '😊';
      case LivenessChallenge.turnLeft:    return '◀';
      case LivenessChallenge.turnRight:   return '▶';
    }
  }
}

class LivenessResult {
  final String imagePath;
  final Uint8List? imageBytes;  // use for Image.memory()
  final List<LivenessChallenge> challengesPassed;
  final DateTime capturedAt;
  final Map<String, dynamic>? metadata;

  LivenessResult({
    required this.imagePath,
    this.imageBytes,
    required this.challengesPassed,
    required this.capturedAt,
    this.metadata,
  });
}
