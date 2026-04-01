import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import 'ai_service.dart';
import 'location_service.dart';
import 'pick_location_page.dart';
import 'report_service.dart';

class ReportIssuePage extends StatefulWidget {
  final String? prefilledAreaName;
  final double? prefilledLat;
  final double? prefilledLng;
  final String source;

  final String? reportId;
  final Map<String, dynamic>? reportData;

  const ReportIssuePage({
    super.key,
    this.prefilledAreaName,
    this.prefilledLat,
    this.prefilledLng,
    required this.source,
    this.reportId,
    this.reportData,
  });

  const ReportIssuePage.edit({
    super.key,
    required this.reportId,
    required this.reportData,
    required this.source,
  })  : prefilledAreaName = null,
        prefilledLat = null,
        prefilledLng = null;

  bool get isEditMode => reportId != null && reportData != null;

  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final List<XFile> _images = [];
  final List<String> _existingImageUrls = [];
  final AiService _aiService = AiService();

  static const int _maxImages = 3;
  static const int _maxImageBytes = 10 * 1024 * 1024;
  static const double _duplicateRadiusMeters = 80;

  double? _latitude;
  double? _longitude;

  String? _locationLabel;
  bool _loadingAddress = false;
  bool _submitting = false;

  bool _aiReady = false;
  bool _isAnalyzingImage = false;
  String? _aiCategory;
  double? _aiConfidence;
  Map<String, dynamic>? _aiScores;

  int _locationLookupToken = 0;

  bool get _isEditMode => widget.isEditMode;
  int get _totalImageCount => _existingImageUrls.length + _images.length;

  @override
  void initState() {
    super.initState();
    _initAi();

    if (_isEditMode) {
      _loadExistingReport();
    } else if (widget.prefilledLat != null && widget.prefilledLng != null) {
      _latitude = widget.prefilledLat;
      _longitude = widget.prefilledLng;

      final initialLabel = widget.prefilledAreaName?.trim();
      if (initialLabel != null && initialLabel.isNotEmpty) {
        _locationLabel = initialLabel;
      } else {
        _locationLabel = "Fetching location...";
      }

      if (_locationStillLoadingText || _locationLooksLikeCoordinates) {
        _fetchShortLocationLabel();
      }
    }
  }

  void _loadExistingReport() {
    final data = widget.reportData ?? {};
    final location = (data['location'] as Map?)?.cast<String, dynamic>() ?? {};

    _titleController.text = (data['title'] ?? '').toString();
    _descriptionController.text =
        (data['description'] ?? data['reason'] ?? '').toString();

    _latitude = (location['lat'] ?? data['latitude']) is num
        ? ((location['lat'] ?? data['latitude']) as num).toDouble()
        : null;

    _longitude = (location['lng'] ?? data['longitude']) is num
        ? ((location['lng'] ?? data['longitude']) as num).toDouble()
        : null;

    _locationLabel = (location['label'] ?? data['address'] ?? '').toString();

    final existingUrls = (data['imageUrls'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList() ??
        [];
    _existingImageUrls.addAll(existingUrls);

    _aiCategory = (data['aiCategory'] ?? data['category'])?.toString();
    _aiConfidence = (data['aiConfidence'] as num?)?.toDouble();
  }

  Future<void> _initAi() async {
    try {
      await _aiService.loadModel();
      if (!mounted) return;
      setState(() {
        _aiReady = true;
      });
    } catch (e) {
      debugPrint("Failed to load AI model: $e");
    }
  }

  bool get _locationStillLoadingText {
    final label = (_locationLabel ?? '').trim().toLowerCase();
    return label == 'fetching location...';
  }

  bool get _locationLooksLikeCoordinates {
    final label = (_locationLabel ?? '').trim().toLowerCase();
    return label.startsWith('lat ') || label.contains('lng ');
  }

  String _normalizeAiCategory(String label) {
    switch (label.trim().toLowerCase()) {
      case 'blocked drainage':
        return 'Blocked Drainage';
      case 'general litter':
        return 'General Litter';
      case 'illegal dumping':
        return 'Illegal Dumping';
      case 'hazardous waste':
        return 'Hazardous Waste';
      case 'pest infestation':
        return 'Pest Infestation';
      case 'overflowing bin':
        return 'Overflowing Bin';
      default:
        return label;
    }
  }

  String _confidenceText(double confidence) {
    if (confidence >= 0.85) return "High";
    if (confidence >= 0.70) return "Moderate";
    return "Low";
  }

  String _getAiUrgency(String category) {
    switch (category) {
      case 'General Litter':
        return 'Low';
      case 'Overflowing Bin':
      case 'Blocked Drainage':
        return 'Medium';
      case 'Illegal Dumping':
      case 'Hazardous Waste':
      case 'Pest Infestation':
        return 'High';
      default:
        return 'Low';
    }
  }

  Future<void> _analyzeFirstImage() async {
    if (!_aiReady || _images.isEmpty) return;

    setState(() {
      _isAnalyzingImage = true;
      _aiCategory = null;
      _aiConfidence = null;
      _aiScores = null;
    });

    try {
      final result = await _aiService.predictImage(File(_images.first.path));
      final rawLabel = result['label'] as String? ?? 'Other';
      final normalizedLabel = _normalizeAiCategory(rawLabel);
      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
      final scores =
          (result['scores'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
              <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        _aiCategory = normalizedLabel;
        _aiConfidence = confidence;
        _aiScores = scores;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("AI prediction failed: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzingImage = false;
        });
      }
    }
  }

  void _clearAiResult() {
    setState(() {
      _aiCategory = null;
      _aiConfidence = null;
      _aiScores = null;
    });
  }

  Future<void> _fetchShortLocationLabel({bool forceReplace = false}) async {
    if (_latitude == null || _longitude == null) return;

    final requestToken = ++_locationLookupToken;
    final requestLat = _latitude!;
    final requestLng = _longitude!;

    setState(() => _loadingAddress = true);

    final label = await LocationService.reverseGeocodeShortLabel(
      lat: requestLat,
      lng: requestLng,
    );

    if (!mounted) return;
    if (requestToken != _locationLookupToken) return;
    if (_latitude != requestLat || _longitude != requestLng) return;

    final currentLabel = (_locationLabel ?? '').trim();
    final shouldReplace = forceReplace ||
        currentLabel.isEmpty ||
        _locationStillLoadingText ||
        _locationLooksLikeCoordinates;

    setState(() {
      _loadingAddress = false;

      if (shouldReplace && label != null && label.trim().isNotEmpty) {
        _locationLabel = label.trim();
      } else if (currentLabel.isEmpty) {
        _locationLabel = "Unknown location";
      }
    });
  }

  Future<void> _useCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location services are disabled")),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied")),
        );
        return;
      }

      setState(() {
        _loadingAddress = true;
        _locationLabel = "Fetching location...";
      });

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );

      if (!mounted) return;

      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });

      await _fetchShortLocationLabel(forceReplace: true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingAddress = false;
        _locationLabel = "Unable to get current location";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to get current location: $e")),
      );
    }
  }

  String _formatFileSize(int bytes) {
    final kb = bytes / 1024;
    final mb = kb / 1024;
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${kb.toStringAsFixed(0)} KB';
  }

  Future<bool> _isValidImageSize(XFile file) async {
    final length = await file.length();
    return length <= _maxImageBytes;
  }

  Future<void> _showTooLargeMessage(XFile file) async {
    final length = await file.length();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Image too large (${_formatFileSize(length)}). Please choose an image under 10 MB.',
        ),
      ),
    );
  }

  Future<void> _pickImagesFromGallery() async {
    try {
      if (_totalImageCount >= _maxImages) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Maximum $_maxImages images allowed")),
        );
        return;
      }

      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;

      final existingPaths = _images.map((e) => e.path).toSet();
      int addedCount = 0;
      bool firstNewImageAdded = false;

      for (final x in picked) {
        if (_totalImageCount >= _maxImages) break;
        if (existingPaths.contains(x.path)) continue;

        final valid = await _isValidImageSize(x);
        if (!valid) {
          await _showTooLargeMessage(x);
          continue;
        }

        _images.add(x);
        existingPaths.add(x.path);
        addedCount++;

        if (!firstNewImageAdded) {
          firstNewImageAdded = true;
        }
      }

      if (!mounted) return;
      setState(() {});

      if (picked.isNotEmpty && addedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No new valid images were added.")),
        );
      } else if (_totalImageCount >= _maxImages) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Maximum $_maxImages images reached")),
        );
      }

      if (firstNewImageAdded) {
        await _analyzeFirstImage();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to pick images: $e")),
      );
    }
  }

  Future<void> _takePhotoWithCamera() async {
    try {
      if (_totalImageCount >= _maxImages) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Maximum $_maxImages images allowed")),
        );
        return;
      }

      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (shot == null) return;

      final valid = await _isValidImageSize(shot);
      if (!valid) {
        await _showTooLargeMessage(shot);
        return;
      }

      bool added = false;

      setState(() {
        if (!_images.any((e) => e.path == shot.path)) {
          _images.add(shot);
          added = true;
        }
      });

      if (added) {
        await _analyzeFirstImage();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to open camera: $e")),
      );
    }
  }

  void _removeImageAt(int index) {
    final removedFirst = index == 0;

    setState(() => _images.removeAt(index));

    if (_images.isEmpty) {
      if (_existingImageUrls.isEmpty) {
        _clearAiResult();
      }
      return;
    }

    if (removedFirst) {
      _analyzeFirstImage();
    }
  }

  void _removeExistingImageAt(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
    });

    if (_totalImageCount == 0) {
      _clearAiResult();
    }
  }

  Future<void> _pickLocationOnMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PickLocationPage(
          initialLat: _latitude,
          initialLng: _longitude,
        ),
      ),
    );

    if (result == null) return;

    _locationLookupToken++;

    if (result is Map) {
      final point = result['point'];
      final label = result['label'];

      if (point is LatLng) {
        final cleanLabel =
            (label is String && label.trim().isNotEmpty) ? label.trim() : null;

        setState(() {
          _latitude = point.latitude;
          _longitude = point.longitude;
          _locationLabel = cleanLabel ?? "Fetching location...";
          _loadingAddress = false;
        });

        if (cleanLabel == null ||
            cleanLabel.toLowerCase() == 'fetching location...' ||
            cleanLabel.toLowerCase().startsWith('lat ') ||
            cleanLabel.toLowerCase().contains('lng ')) {
          await _fetchShortLocationLabel();
        }
      }
      return;
    }

    if (result is LatLng) {
      setState(() {
        _latitude = result.latitude;
        _longitude = result.longitude;
        _locationLabel = "Fetching location...";
        _loadingAddress = false;
      });

      await _fetchShortLocationLabel();
    }
  }

  Future<bool> _hasNearbyActiveReportBySameUser() async {
    if (_latitude == null || _longitude == null) return false;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    final currentUserId = currentUser.uid;

    final snapshot = await FirebaseFirestore.instance
        .collection('reports')
        .where('userId', isEqualTo: currentUserId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final location = (data['location'] as Map?)?.cast<String, dynamic>();

      final lat = (location?['lat'] ?? data['latitude']) as num?;
      final lng = (location?['lng'] ?? data['longitude']) as num?;

      if (lat == null || lng == null) continue;

      final status = (data['status'] ?? 'pending').toString().toLowerCase();

      if (status == 'resolved' ||
          status == 'completed' ||
          status == 'closed' ||
          status == 'cleaned') {
        continue;
      }

      final distance = Geolocator.distanceBetween(
        _latitude!,
        _longitude!,
        lat.toDouble(),
        lng.toDouble(),
      );

      if (distance <= _duplicateRadiusMeters) {
        return true;
      }
    }

    return false;
  }

  Future<void> _submitReport() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select location")),
      );
      return;
    }

    if (_loadingAddress || _locationStillLoadingText) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please wait until the location is fully loaded"),
        ),
      );
      return;
    }

    if (_totalImageCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload at least 1 proof image")),
      );
      return;
    }

    if (_aiCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please wait for AI image analysis")),
      );
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final aiCategory = _aiCategory!;
    final urgency = _getAiUrgency(aiCategory);
    final locationLabel =
        (_locationLabel == null || _locationLabel!.trim().isEmpty)
            ? "Unknown location"
            : _locationLabel!.trim();

    setState(() => _submitting = true);

    try {
      if (!_isEditMode) {
        final exists = await _hasNearbyActiveReportBySameUser();

        if (exists) {
          if (mounted) {
            setState(() => _submitting = false);
          }

          if (!mounted) return;

          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Duplicate Report Detected"),
              content: const Text(
                "You have already submitted an active report for this location.\n\n"
                "You cannot submit another report for the same place until the current one is resolved.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
          return;
        }
      }

      final imageFiles = _images.map((x) => File(x.path)).toList();

      if (_isEditMode) {
        await ReportService.updateReport(
          reportId: widget.reportId!,
          title: title,
          category: aiCategory,
          description: description,
          urgency: urgency,
          latitude: _latitude!,
          longitude: _longitude!,
          locationLabel: locationLabel,
          newImageFiles: imageFiles,
          retainedImageUrls: _existingImageUrls,
          source: widget.source,
          aiConfidence: _aiConfidence,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Report updated successfully")),
        );
      } else {
        final reportId = await ReportService.submitReport(
          title: title,
          category: aiCategory,
          description: description,
          urgency: urgency,
          latitude: _latitude!,
          longitude: _longitude!,
          locationLabel: locationLabel,
          imageFiles: imageFiles,
          source: widget.source,
          aiConfidence: _aiConfidence,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Report submitted (ID: $reportId)")),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_isEditMode ? "Update failed: $e" : "Submit failed: $e"),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool submitDisabled =
        _submitting ||
        _loadingAddress ||
        _locationStillLoadingText ||
        _isAnalyzingImage;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4EF),
      appBar: AppBar(
        title: Text(_isEditMode ? "Edit Report" : "Report Issue"),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Report Title",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      hintText: "Enter report title...",
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return "Report title is required";
                      }
                      if (v.trim().length < 5) {
                        return "Please write at least 5 characters";
                      }
                      return null;
                    },
                  ),
                  if (_isAnalyzingImage) ...[
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text("Analyzing image with AI..."),
                      ],
                    ),
                  ],
                  if (_aiCategory != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        border: Border.all(color: Colors.green.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "AI Detected Category: $_aiCategory",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Confidence: ${((_aiConfidence ?? 0) * 100).toStringAsFixed(1)}% "
                            "(${_confidenceText(_aiConfidence ?? 0)})",
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "AI Dirtiness Level: ${_getAiUrgency(_aiCategory!)}",
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    "Description",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: "Describe the issue...",
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return "Description is required";
                      }
                      if (v.trim().length < 10) {
                        return "Please write at least 10 characters";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Upload Images",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickImagesFromGallery,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text("Gallery"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _takePhotoWithCamera,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text("Camera"),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_totalImageCount == 0)
                          Container(
                            height: 110,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F3F3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: const Text(
                              "No images selected",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          )
                        else ...[
                          if (_existingImageUrls.isNotEmpty) ...[
                            const Text(
                              "Existing Images",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _existingImageUrls.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemBuilder: (context, index) {
                                final imageUrl = _existingImageUrls[index];
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        imageUrl,
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: InkWell(
                                        onTap: () =>
                                            _removeExistingImageAt(index),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.6),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_images.isNotEmpty) ...[
                            const Text(
                              "New Images",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _images.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemBuilder: (context, index) {
                                final x = _images[index];
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(x.path),
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: InkWell(
                                        onTap: () => _removeImageAt(index),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.6),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                        const SizedBox(height: 6),
                        Text(
                          "Selected: $_totalImageCount / $_maxImages",
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Each image must be under 10 MB.",
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "AI will analyze the first new selected image.",
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Location",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: _pickLocationOnMap,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F7F7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.search,
                                  color: Color(0xFF2E7D32),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    (_locationLabel == null ||
                                            _locationLabel!.trim().isEmpty)
                                        ? "Search or pick a location"
                                        : _locationLabel!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: (_locationLabel == null ||
                                              _locationLabel!.trim().isEmpty)
                                          ? Colors.black45
                                          : Colors.black87,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_loadingAddress)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.black45,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _useCurrentLocation,
                                icon: const Icon(Icons.my_location),
                                label: const Text("Use Current"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2E7D32),
                                  side: const BorderSide(
                                    color: Color(0xFF2E7D32),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickLocationOnMap,
                                icon: const Icon(Icons.map_outlined),
                                label: const Text("Pick on Map"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2E7D32),
                                  side: const BorderSide(
                                    color: Color(0xFF2E7D32),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_loadingAddress || _locationStillLoadingText) ...[
                          const SizedBox(height: 8),
                          const Text(
                            "Please wait while the location is being loaded.",
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: submitDisabled ? null : _submitReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5E9F52),
                        disabledBackgroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 4,
                      ),
                      child: Text(
                        _submitting
                            ? (_isEditMode ? "Updating..." : "Submitting...")
                            : _loadingAddress || _locationStillLoadingText
                                ? "Waiting for location..."
                                : _isAnalyzingImage
                                    ? "Analyzing image..."
                                    : (_isEditMode
                                        ? "Update Report"
                                        : "Submit Report"),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_submitting)
            Container(
              color: Colors.black.withOpacity(0.15),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}