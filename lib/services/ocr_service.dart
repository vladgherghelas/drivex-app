import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';

@JS('ocrFromBytes')
external JSPromise<JSString> _ocrFromBytes(JSString base64Data);

@JS('detectMotion')
external JSPromise<JSNumber> _detectMotion(JSString b64a, JSString b64b);

@JS('checkFacePresence')
external JSPromise<JSString> _checkFacePresence(JSString b64);

/// Face detection result with position and yaw angle.
class FaceData {
  final int score;       // 0-100 confidence
  final double cx, cy;   // face center normalized 0-1
  final double faceW;    // face width normalized 0-1
  final double yaw;      // head rotation: negative=left, positive=right

  FaceData({this.score = 0, this.cx = 0.5, this.cy = 0.5, this.faceW = 0, this.yaw = 0});

  factory FaceData.fromJson(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return FaceData(
        score: (m['score'] as num?)?.toInt() ?? 0,
        cx: (m['cx'] as num?)?.toDouble() ?? 0.5,
        cy: (m['cy'] as num?)?.toDouble() ?? 0.5,
        faceW: (m['faceW'] as num?)?.toDouble() ?? 0,
        yaw: (m['yaw'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) { return FaceData(); }
  }

  bool get hasFace => score > 0;
}

/// Runs in-browser OCR on image bytes via Tesseract.js.
Future<String> ocrRecognize(Uint8List imageBytes) async {
  try {
    final b64 = base64Encode(imageBytes);
    final result = await _ocrFromBytes(b64.toJS).toDart;
    return result.toDart;
  } catch (e) {
    return '';
  }
}

/// Compares two frames and returns motion score (0-100).
Future<int> detectFrameMotion(Uint8List a, Uint8List b) async {
  try {
    final r = await _detectMotion(base64Encode(a).toJS, base64Encode(b).toJS).toDart;
    return r.toDartInt;
  } catch (_) { return 0; }
}

/// Full face detection with position + yaw.
Future<FaceData> checkForFaceData(Uint8List bytes) async {
  try {
    final r = await _checkFacePresence(base64Encode(bytes).toJS).toDart;
    return FaceData.fromJson(r.toDart);
  } catch (_) { return FaceData(); }
}

/// Legacy: returns just the score (0-100).
Future<int> checkForFace(Uint8List bytes) async {
  final d = await checkForFaceData(bytes);
  return d.score;
}

/// Parses OCR text and extracts document fields.
class OcrResult {
  final String rawText;
  final String? name;
  final String? dateOfBirth;
  final String? expiryDate;
  final String? documentNumber;
  final bool isDocument;

  OcrResult({required this.rawText, this.name, this.dateOfBirth, this.expiryDate, this.documentNumber, required this.isDocument});

  factory OcrResult.fromText(String text) {
    if (text.trim().length < 10) return OcrResult(rawText: text, isDocument: false);

    final upper = text.toUpperCase();

    // Document indicators — keywords found on IDs, licenses, passports
    final docKeywords = ['LICENSE', 'LICENCE', 'DRIVER', 'PASSPORT', 'IDENTITY', 'NATIONAL',
      'REPUBLIC', 'DATE OF BIRTH', 'DOB', 'EXPIRY', 'EXPIRES', 'EXP', 'VALID',
      'SURNAME', 'GIVEN NAME', 'FIRST NAME', 'LAST NAME', 'SEX', 'NATIONALITY',
      'PLACE OF BIRTH', 'ISSUED', 'AUTHORITY', 'CLASS', 'CATEGORY', 'ADDRESS',
      'PERMIS', 'CONDUIRE', 'CARTE', 'IDENTITE', 'BULETIN', 'CNP', 'SERIA', 'NR'];

    int keywordHits = 0;
    for (final kw in docKeywords) {
      if (upper.contains(kw)) keywordHits++;
    }

    // Date pattern: DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY, YYYY-MM-DD
    final dateRegex = RegExp(r'\b(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}|\d{4}[/\-\.]\d{1,2}[/\-\.]\d{1,2})\b');
    final dates = dateRegex.allMatches(text).map((m) => m.group(0)!).toList();

    // Document number pattern: series of digits/letters (e.g., AB123456, 123456789)
    final docNumRegex = RegExp(r'\b[A-Z]{0,3}\d{5,12}\b');
    final docNums = docNumRegex.allMatches(upper).map((m) => m.group(0)!).toList();

    // Name extraction: look for lines after "NAME" or "SURNAME" keywords
    String? extractedName;
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (int i = 0; i < lines.length; i++) {
      final lineUp = lines[i].toUpperCase();
      if (lineUp.contains('NAME') || lineUp.contains('SURNAME') || lineUp.contains('NUMELE')) {
        // Name might be on the same line after a colon, or on the next line
        final colonIdx = lines[i].indexOf(':');
        if (colonIdx >= 0 && colonIdx < lines[i].length - 2) {
          extractedName = lines[i].substring(colonIdx + 1).trim();
        } else if (i + 1 < lines.length) {
          extractedName = lines[i + 1].trim();
        }
        break;
      }
    }

    // Consider it a document if ≥3 keyword hits OR (≥2 keywords + ≥1 date)
    final isDoc = keywordHits >= 3 || (keywordHits >= 2 && dates.isNotEmpty) || (keywordHits >= 1 && dates.length >= 2);

    return OcrResult(
      rawText: text,
      isDocument: isDoc,
      name: extractedName,
      dateOfBirth: dates.isNotEmpty ? dates.first : null,
      expiryDate: dates.length > 1 ? dates.last : null,
      documentNumber: docNums.isNotEmpty ? docNums.first : null,
    );
  }
}
