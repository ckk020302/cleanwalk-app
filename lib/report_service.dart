import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ReportService {
  static const int defaultQuorumThreshold = 3;

  static const String _detectTrashUrl =
      'https://us-central1-cleanwalk-84ca5.cloudfunctions.net/detectTrash';

  static Future<File> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        "${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg";

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70,
    );

    if (result == null) return file;
    return File(result.path);
  }

  static String _toCategoryKey(String category) {
    return category
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static Future<Map<String, dynamic>> _detectAiFromCloud({
    required String category,
    required String description,
    required String urgency,
    required int imageCount,
    required String reportId,
    double? aiConfidence,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(_detectTrashUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'category': category,
              'description': description,
              'reportId': reportId,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        final detectedSeverity =
            (data['detectedSeverity'] ?? 'Low').toString().trim();

        int detectedScore = 30;
        final rawScore = data['detectedScore'];

        if (rawScore is int) {
          detectedScore = rawScore;
        } else if (rawScore is num) {
          detectedScore = rawScore.toInt();
        }

        if (imageCount >= 2) detectedScore += 5;
        if (imageCount >= 3) detectedScore += 5;

        if (detectedScore > 100) detectedScore = 100;

        String finalSeverity = detectedSeverity;
        if (detectedSeverity.isEmpty) {
          if (detectedScore >= 70) {
            finalSeverity = 'High';
          } else if (detectedScore >= 40) {
            finalSeverity = 'Medium';
          } else {
            finalSeverity = 'Low';
          }
        }

        final rawCategoryScore = data['categoryScore'];
        final rawDescriptionScore = data['descriptionScore'];
        final rawImageScore = data['imageScore'];

        int categoryScore = 0;
        int descriptionScore = 0;
        int imageScore = 0;

        if (rawCategoryScore is int) categoryScore = rawCategoryScore;
        if (rawCategoryScore is num) categoryScore = rawCategoryScore.toInt();

        if (rawDescriptionScore is int) descriptionScore = rawDescriptionScore;
        if (rawDescriptionScore is num) {
          descriptionScore = rawDescriptionScore.toInt();
        }

        if (rawImageScore is int) imageScore = rawImageScore;
        if (rawImageScore is num) imageScore = rawImageScore.toInt();

        final labels = (data['labels'] is List)
            ? List<Map<String, dynamic>>.from(
                (data['labels'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              )
            : <Map<String, dynamic>>[];

        final objects = (data['objects'] is List)
            ? List<Map<String, dynamic>>.from(
                (data['objects'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              )
            : <Map<String, dynamic>>[];

        return {
          'issueCategory': category,
          'issueCategoryKey': _toCategoryKey(category),
          'aiSource': 'firebase_cloud_vision',
          'aiModel': 'google_cloud_vision_hybrid_v1',
          'aiStatus': 'analyzed',
          'aiSeverity': finalSeverity.toLowerCase(),
          'aiScore': detectedScore,
          'aiConfidence': aiConfidence ?? 0.85,
          'aiReason':
              'Severity generated using category, description, and Cloud Vision image analysis.',
          'aiDetections': imageCount,
          'aiConfidenceAvg': aiConfidence ?? 0.85,
          'aiCategoryScore': categoryScore,
          'aiDescriptionScore': descriptionScore,
          'aiImageScore': imageScore,
          'aiLabels': labels,
          'aiObjects': objects,
        };
      }
    } catch (e) {
      print('AI detection failed: $e');
    }

    return _buildFallbackAiResult(
      category: category,
      urgency: urgency,
      imageCount: imageCount,
      aiConfidence: aiConfidence,
    );
  }

  static Map<String, dynamic> _buildFallbackAiResult({
    required String category,
    required String urgency,
    required int imageCount,
    double? aiConfidence,
  }) {
    int score = 30;

    if (category == "Illegal Dumping") score = 85;
    if (category == "Hazardous Waste") score = 95;
    if (category == "Blocked Drainage") score = 80;
    if (category == "Overflowing Bin") score = 55;
    if (category == "Pest Infestation") score = 90;

    if (imageCount >= 2) score += 5;
    if (imageCount >= 3) score += 5;

    if (score > 100) score = 100;

    String severity = "low";

    if (score >= 70) {
      severity = "high";
    } else if (score >= 40) {
      severity = "medium";
    }

    return {
      'issueCategory': category,
      'issueCategoryKey': _toCategoryKey(category),
      'aiSource': 'fallback_rule_engine',
      'aiModel': 'cleanwalk_fallback_v1',
      'aiStatus': 'fallback',
      'aiSeverity': severity,
      'aiScore': score,
      'aiConfidence': aiConfidence ?? 0.7,
      'aiReason': 'Fallback rule-based scoring used.',
      'aiDetections': imageCount,
      'aiConfidenceAvg': aiConfidence ?? 0.7,
      'aiCategoryScore': 0,
      'aiDescriptionScore': 0,
      'aiImageScore': 0,
      'aiLabels': <Map<String, dynamic>>[],
      'aiObjects': <Map<String, dynamic>>[],
    };
  }

  static Future<String> _loadReporterName(User? user) async {
    if (user == null) return 'Unknown User';

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = userDoc.data() ?? {};

      final fullName = (data['fullName'] as String?)?.trim();
      final username = (data['username'] as String?)?.trim();
      final name = (data['name'] as String?)?.trim();

      if (fullName != null && fullName.isNotEmpty) return fullName;
      if (username != null && username.isNotEmpty) return username;
      if (name != null && name.isNotEmpty) return name;

      final authDisplayName = user.displayName?.trim();
      if (authDisplayName != null && authDisplayName.isNotEmpty) {
        return authDisplayName;
      }

      return user.email ?? 'Unknown User';
    } catch (e) {
      return user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email ?? 'Unknown User');
    }
  }

  static Future<List<String>> _uploadImages({
    required String reportId,
    required List<File> imageFiles,
    required List<String> retainedImageUrls,
  }) async {
    final storage = FirebaseStorage.instance;
    final imageUrls = <String>[...retainedImageUrls];

    for (int i = 0; i < imageFiles.length; i++) {
      final compressedFile = await _compressImage(imageFiles[i]);

      final storageRef = storage
          .ref()
          .child(
            'reports/$reportId/image_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
          );

      final uploadTask = await storageRef.putFile(compressedFile);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      imageUrls.add(downloadUrl);
    }

    return imageUrls;
  }

  static Future<void> _deleteRemovedImages({
    required List<String> oldImageUrls,
    required List<String> retainedImageUrls,
  }) async {
    final removedUrls = oldImageUrls
        .where((url) => !retainedImageUrls.contains(url))
        .toList();

    for (final url in removedUrls) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }
  }

  static Future<String> submitReport({
    required String title,
    required String category,
    required String description,
    required String urgency,
    required double latitude,
    required double longitude,
    required String locationLabel,
    required List<File> imageFiles,
    required String source,
    double? aiConfidence,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('User not logged in');
    }

    final reporterName = await _loadReporterName(user);

    final docRef = firestore.collection('reports').doc();
    final reportId = docRef.id;

    final imageUrls = await _uploadImages(
      reportId: reportId,
      imageFiles: imageFiles,
      retainedImageUrls: const [],
    );

    final aiResult = await _detectAiFromCloud(
      category: category,
      description: description,
      urgency: urgency,
      imageCount: imageUrls.length,
      reportId: reportId,
      aiConfidence: aiConfidence,
    );

    final quorumThreshold =
        aiResult['issueCategoryKey'] == 'pest_infestation' ||
                aiResult['issueCategoryKey'] == 'hazardous_waste' ||
                aiResult['issueCategoryKey'] == 'illegal_dumping' ||
                aiResult['issueCategoryKey'] == 'blocked_drainage'
            ? 2
            : defaultQuorumThreshold;

    await docRef.set({
      'reportId': reportId,
      'userId': user.uid,
      'reportedBy': reporterName,
      'reporterName': reporterName,
      'reporterEmail': user.email,
      'title': title,
      'category': category,
      'description': description,
      'reason': description,
      'urgency': urgency,
      'severity': aiResult['aiSeverity'],
      'location': {
        'lat': latitude,
        'lng': longitude,
        'label': locationLabel,
      },
      'latitude': latitude,
      'longitude': longitude,
      'address': locationLabel,
      'imageUrls': imageUrls,
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
      'aiCategory': category,
      'aiSource': aiResult['aiSource'],
      'aiModel': aiResult['aiModel'],
      'aiStatus': aiResult['aiStatus'],
      'aiSeverity': aiResult['aiSeverity'],
      'aiScore': aiResult['aiScore'],
      'aiConfidence': aiResult['aiConfidence'],
      'aiReason': aiResult['aiReason'],
      'aiDetections': aiResult['aiDetections'],
      'aiConfidenceAvg': aiResult['aiConfidenceAvg'],
      'aiCategoryScore': aiResult['aiCategoryScore'],
      'aiDescriptionScore': aiResult['aiDescriptionScore'],
      'aiImageScore': aiResult['aiImageScore'],
      'aiLabels': aiResult['aiLabels'],
      'aiObjects': aiResult['aiObjects'],
      'confirmCount': 0,
      'confirmedBy': <String>[],
      'quorumThreshold': quorumThreshold,
      'quorumReached': false,
      'verificationStatus': 'pending',
      'status': 'pending',
    });

    return reportId;
  }

  static Future<void> updateReport({
    required String reportId,
    required String title,
    required String category,
    required String description,
    required String urgency,
    required double latitude,
    required double longitude,
    required String locationLabel,
    required List<File> newImageFiles,
    required List<String> retainedImageUrls,
    required String source,
    double? aiConfidence,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('User not logged in');
    }

    final docRef = firestore.collection('reports').doc(reportId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      throw Exception('Report not found');
    }

    final existingData = snapshot.data() ?? {};
    if (existingData['userId'] != user.uid) {
      throw Exception('You can only edit your own report');
    }

    final oldImageUrls = (existingData['imageUrls'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final updatedImageUrls = await _uploadImages(
      reportId: reportId,
      imageFiles: newImageFiles,
      retainedImageUrls: retainedImageUrls,
    );

    await _deleteRemovedImages(
      oldImageUrls: oldImageUrls,
      retainedImageUrls: retainedImageUrls,
    );

    if (updatedImageUrls.isEmpty) {
      throw Exception('At least one image is required');
    }

    final aiResult = await _detectAiFromCloud(
      category: category,
      description: description,
      urgency: urgency,
      imageCount: updatedImageUrls.length,
      reportId: reportId,
      aiConfidence: aiConfidence,
    );

    final quorumThreshold =
        aiResult['issueCategoryKey'] == 'pest_infestation' ||
                aiResult['issueCategoryKey'] == 'hazardous_waste' ||
                aiResult['issueCategoryKey'] == 'illegal_dumping' ||
                aiResult['issueCategoryKey'] == 'blocked_drainage'
            ? 2
            : defaultQuorumThreshold;

    await docRef.update({
      'title': title,
      'category': category,
      'description': description,
      'reason': description,
      'urgency': urgency,
      'severity': aiResult['aiSeverity'],
      'location': {
        'lat': latitude,
        'lng': longitude,
        'label': locationLabel,
      },
      'latitude': latitude,
      'longitude': longitude,
      'address': locationLabel,
      'imageUrls': updatedImageUrls,
      'source': source,
      'updatedAt': FieldValue.serverTimestamp(),
      'aiCategory': category,
      'aiSource': aiResult['aiSource'],
      'aiModel': aiResult['aiModel'],
      'aiStatus': aiResult['aiStatus'],
      'aiSeverity': aiResult['aiSeverity'],
      'aiScore': aiResult['aiScore'],
      'aiConfidence': aiResult['aiConfidence'],
      'aiReason': aiResult['aiReason'],
      'aiDetections': aiResult['aiDetections'],
      'aiConfidenceAvg': aiResult['aiConfidenceAvg'],
      'aiCategoryScore': aiResult['aiCategoryScore'],
      'aiDescriptionScore': aiResult['aiDescriptionScore'],
      'aiImageScore': aiResult['aiImageScore'],
      'aiLabels': aiResult['aiLabels'],
      'aiObjects': aiResult['aiObjects'],
      'quorumThreshold': quorumThreshold,
    });
  }

  static Future<void> deleteReport({
    required String reportId,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('User not logged in');
    }

    final docRef = firestore.collection('reports').doc(reportId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      throw Exception('Report not found');
    }

    final data = snapshot.data() ?? {};
    if (data['userId'] != user.uid) {
      throw Exception('You can only delete your own report');
    }

    final imageUrls = (data['imageUrls'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    for (final url in imageUrls) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }

    await docRef.delete();
  }
}