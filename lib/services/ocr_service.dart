import 'package:google_ml_kit/google_ml_kit.dart';

class OcrService {
  OcrService() : _textRecognizer = GoogleMlKit.vision.textRecognizer();

  final TextRecognizer _textRecognizer;

  Future<String> scanTextFromImagePath(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(
      inputImage,
    );
    return recognizedText.text;
  }

  String? detectErrorCode(String rawText) {
    final regex = RegExp(
      r'\b(ALARM|ERROR)\s*[-:]?\s*(\d{3,5})\b',
      caseSensitive: false,
    );
    final match = regex.firstMatch(rawText.toUpperCase());
    if (match == null) {
      return null;
    }
    final type = match.group(1) ?? '';
    final number = match.group(2) ?? '';
    return '$type $number'.trim();
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
