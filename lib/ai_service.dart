import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class AiService {
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;
  AiService._internal();

  Interpreter? _interpreter;

  // IMPORTANT:
  // These labels must follow the same class order used during training.
  // From your Colab output:
  // {'Blocked Drainage': 0, 'General Litter': 1, 'Illegal Dumping': 2, 'Overflowing bin': 3, 'Pest Infestation': 4}
  final List<String> _labels = const [
    'Blocked Drainage',
    'General Litter',
    'Illegal Dumping',
    'Overflowing Bin',
    'Pest Infestation',
  ];

  bool get isLoaded => _interpreter != null;

  Future<void> loadModel() async {
    if (_interpreter != null) return;

    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/cleanwalk_model.tflite',
      );

      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final inputType = _interpreter!.getInputTensor(0).type;
      final outputType = _interpreter!.getOutputTensor(0).type;

      print('AI model loaded successfully');
      print('Input shape: $inputShape');
      print('Input type: $inputType');
      print('Output shape: $outputShape');
      print('Output type: $outputType');

      final numClasses = outputShape.last;
      if (numClasses != _labels.length) {
        throw Exception(
          'Label count (${_labels.length}) does not match model output classes ($numClasses).',
        );
      }
    } catch (e) {
      throw Exception('Failed to load TFLite model: $e');
    }
  }

  Future<Map<String, dynamic>> predictImage(File imageFile) async {
    if (_interpreter == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    final interpreter = _interpreter!;

    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;

    if (inputShape.length != 4) {
      throw Exception('Unexpected input shape: $inputShape');
    }

    final inputHeight = inputShape[1];
    final inputWidth = inputShape[2];
    final numClasses = outputShape.last;

    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);

    if (decoded == null) {
      throw Exception('Unable to decode image.');
    }

    final resized = img.copyResize(
      decoded,
      width: inputWidth,
      height: inputHeight,
    );

    final input = _imageToInputTensor(
      resized,
      inputWidth: inputWidth,
      inputHeight: inputHeight,
    );

    final output = [List<double>.filled(numClasses, 0.0)];

    interpreter.run(input, output);

    final scores = output.first;

    if (scores.isEmpty) {
      throw Exception('Model returned empty output.');
    }

    int bestIndex = 0;
    double bestScore = scores[0];

    for (int i = 1; i < scores.length; i++) {
      if (scores[i] > bestScore) {
        bestScore = scores[i];
        bestIndex = i;
      }
    }

    if (bestIndex >= _labels.length) {
      throw Exception(
        'Predicted class index $bestIndex is outside label range ${_labels.length}.',
      );
    }

    return {
      'label': _labels[bestIndex],
      'confidence': bestScore,
      'scores': {
        for (int i = 0; i < _labels.length && i < scores.length; i++)
          _labels[i]: scores[i],
      },
    };
  }

  List<List<List<List<double>>>> _imageToInputTensor(
    img.Image image, {
    required int inputWidth,
    required int inputHeight,
  }) {
    return [
      List.generate(
        inputHeight,
        (y) => List.generate(inputWidth, (x) {
          final pixel = image.getPixel(x, y);

          final r = pixel.r.toDouble() / 255.0;
          final g = pixel.g.toDouble() / 255.0;
          final b = pixel.b.toDouble() / 255.0;

          return [r, g, b];
        }),
      ),
    ];
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}