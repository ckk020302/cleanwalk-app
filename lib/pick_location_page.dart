import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

import 'location_service.dart';

class PickLocationPage extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const PickLocationPage({super.key, this.initialLat, this.initialLng});

  @override
  State<PickLocationPage> createState() => _PickLocationPageState();
}

class _PickLocationPageState extends State<PickLocationPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;

  LatLng? _selectedPoint;
  LatLng _center = const LatLng(3.1390, 101.6869); // KL fallback

  bool _loadingLocation = true;
  bool _searching = false;
  bool _resolvingTappedPlace = false;

  List<_SearchResultItem> _searchResults = [];
  String? _selectedLabel;

  int _tapResolveToken = 0;
  int _searchRequestToken = 0;

  @override
  void initState() {
    super.initState();

    if (widget.initialLat != null && widget.initialLng != null) {
      _selectedPoint = LatLng(widget.initialLat!, widget.initialLng!);
      _center = _selectedPoint!;
      _loadingLocation = false;
    } else {
      _initLocation();
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _initLocation() async {
    setState(() => _loadingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _loadingLocation = false);
        _showSnack("Location services are disabled (using KL center).");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() => _loadingLocation = false);
        _showSnack("Location permission denied (using KL center).");
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _loadingLocation = false);
        _showSnack("Location permission denied forever (using KL center).");
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );

      final userPoint = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _center = userPoint;
        _selectedPoint = userPoint;
        _selectedLabel = "Fetching location...";
        _loadingLocation = false;
      });

      _mapController.move(userPoint, 16);
      await _resolveTappedPointLabel(userPoint);
    } catch (_) {
      setState(() => _loadingLocation = false);
      _showSnack("Failed to get GPS (using KL center).");
    }
  }

  String _normalizeMalaysiaQuery(String raw) {
    final q = raw.trim();
    final lower = q.toLowerCase();

    const aliasMap = <String, String>{
      'kl': 'Kuala Lumpur',
      'klcc': 'KLCC Kuala Lumpur',
      'pj': 'Petaling Jaya',
      'jb': 'Johor Bahru',
      'kk': 'Kota Kinabalu',
      'ipoh': 'Ipoh',
      'penang': 'George Town Penang',
      'trx': 'The Exchange TRX Kuala Lumpur',
    };

    if (aliasMap.containsKey(lower)) {
      return aliasMap[lower]!;
    }

    if (lower == 'klc') {
      return 'KLCC Kuala Lumpur';
    }

    return q;
  }

  List<String> _queryTokens(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  int _scoreResult({
    required String originalQuery,
    required String normalizedQuery,
    required Map<String, dynamic> address,
    required String displayName,
  }) {
    final queryLower = originalQuery.toLowerCase().trim();
    final normalizedLower = normalizedQuery.toLowerCase().trim();
    final displayLower = displayName.toLowerCase();

    final nameFields = [
      address['name'],
      address['attraction'],
      address['building'],
      address['shop'],
      address['tourism'],
      address['amenity'],
      address['leisure'],
      address['office'],
      address['mall'],
      address['retail'],
      address['commercial'],
      address['road'],
      address['neighbourhood'],
      address['suburb'],
      address['city'],
      address['town'],
      address['village'],
      address['state'],
    ]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .map((e) => e.toString().toLowerCase())
        .toList();

    final primaryName = nameFields.isNotEmpty ? nameFields.first : '';
    final allText = ([displayLower, ...nameFields]).join(' | ');

    int score = 0;

    if (primaryName == queryLower) score += 200;
    if (primaryName == normalizedLower) score += 220;

    if (displayLower.startsWith(queryLower)) score += 120;
    if (displayLower.startsWith(normalizedLower)) score += 140;

    if (displayLower.contains(queryLower)) score += 80;
    if (displayLower.contains(normalizedLower)) score += 100;

    final tokens = _queryTokens(normalizedQuery);
    for (final token in tokens) {
      if (token.length < 2) continue;
      if (allText.contains(token)) {
        score += 25;
      }
    }

    final exactKeyTerms = <String>[
      'klcc',
      'trx',
      'pavilion',
      'petronas',
      'mid valley',
      'sunway',
      'cheras',
      'ampang',
      'setapak',
    ];

    for (final term in exactKeyTerms) {
      if (queryLower.contains(term) || normalizedLower.contains(term)) {
        if (allText.contains(term)) {
          score += 70;
        }
      }
    }

    final hasLandmarkLikeField = [
      address['name'],
      address['attraction'],
      address['building'],
      address['shop'],
      address['tourism'],
      address['amenity'],
      address['leisure'],
      address['office'],
    ].any((e) => e != null && e.toString().trim().isNotEmpty);

    final onlyBroadArea = !hasLandmarkLikeField &&
        [
          address['suburb'],
          address['neighbourhood'],
          address['city_district'],
          address['city'],
          address['town'],
          address['state'],
        ].any((e) => e != null && e.toString().trim().isNotEmpty);

    if (hasLandmarkLikeField) score += 35;
    if (onlyBroadArea) score -= 20;

    if (displayLower.contains('bukit bintang') &&
        (queryLower.contains('klcc') || normalizedLower.contains('klcc'))) {
      score -= 40;
    }

    return score;
  }

  Future<void> _searchLocation(
    String query, {
    bool showNotFoundSnack = false,
  }) async {
    final q = query.trim();
    final requestToken = ++_searchRequestToken;

    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }

    final normalizedQuery = _normalizeMalaysiaQuery(q);

    setState(() {
      _searching = true;
      _searchResults = [];
    });

    try {
      final url = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': '$normalizedQuery, Malaysia',
          'format': 'jsonv2',
          'limit': '12',
          'countrycodes': 'my',
          'addressdetails': '1',
          'dedupe': '1',
        },
      );

      final response = await http
          .get(
            url,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'CleanWalk-FYP/1.0',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (!mounted || requestToken != _searchRequestToken) return;

      if (response.statusCode != 200) {
        if (showNotFoundSnack) {
          _showSnack("Search failed (${response.statusCode})");
        }
        setState(() => _searching = false);
        return;
      }

      final data = jsonDecode(response.body);

      if (data is List && data.isNotEmpty) {
        final scoredResults = <_RankedSearchResult>[];

        for (final item in data) {
          if (item is! Map<String, dynamic>) continue;

          final lat = double.tryParse((item['lat'] ?? '').toString());
          final lon = double.tryParse((item['lon'] ?? '').toString());
          final displayName = (item['display_name'] ?? '').toString().trim();
          final address =
              (item['address'] as Map?)?.cast<String, dynamic>() ?? {};

          if (lat == null || lon == null) continue;

          final title = _buildNominatimTitle(
            address,
            displayName,
            originalQuery: q,
            normalizedQuery: normalizedQuery,
          );
          final subtitle = _buildNominatimSubtitle(address, displayName);

          final score = _scoreResult(
            originalQuery: q,
            normalizedQuery: normalizedQuery,
            address: address,
            displayName: displayName,
          );

          scoredResults.add(
            _RankedSearchResult(
              item: _SearchResultItem(
                title: title,
                subtitle: subtitle,
                point: LatLng(lat, lon),
              ),
              score: score,
            ),
          );
        }

        scoredResults.sort((a, b) => b.score.compareTo(a.score));

        final results = scoredResults
            .map((e) => e.item)
            .fold<List<_SearchResultItem>>([], (list, item) {
          final exists = list.any(
            (x) =>
                x.title.toLowerCase() == item.title.toLowerCase() &&
                x.subtitle.toLowerCase() == item.subtitle.toLowerCase(),
          );
          if (!exists) list.add(item);
          return list;
        });

        if (!mounted || requestToken != _searchRequestToken) return;

        setState(() {
          _searchResults = results.take(8).toList();
          _searching = false;
        });

        if (results.isEmpty && showNotFoundSnack) {
          _showSnack("Location not found in Malaysia");
        }
      } else {
        if (!mounted || requestToken != _searchRequestToken) return;

        setState(() {
          _searchResults = [];
          _searching = false;
        });

        if (showNotFoundSnack) {
          _showSnack("Location not found in Malaysia");
        }
      }
    } on TimeoutException {
      if (!mounted || requestToken != _searchRequestToken) return;

      setState(() => _searching = false);
      if (showNotFoundSnack) {
        _showSnack("Search timeout. Please try again.");
      }
    } catch (e) {
      debugPrint('Search error: $e');

      if (!mounted || requestToken != _searchRequestToken) return;

      setState(() => _searching = false);
      if (showNotFoundSnack) {
        _showSnack("Search error");
      }
    }
  }

  String _buildNominatimTitle(
    Map<String, dynamic> address,
    String displayName, {
    required String originalQuery,
    required String normalizedQuery,
  }) {
    final displayParts = displayName
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final displayFirst = displayParts.isNotEmpty ? displayParts.first : '';
    final queryLower = originalQuery.toLowerCase();
    final normalizedLower = normalizedQuery.toLowerCase();
    final displayFirstLower = displayFirst.toLowerCase();

    if (displayFirst.isNotEmpty) {
      if (displayFirstLower.contains(queryLower) ||
          displayFirstLower.contains(normalizedLower)) {
        return displayFirst;
      }
    }

    final strongPrimary = _readFirstNonEmpty([
      address['name'],
      address['attraction'],
      address['building'],
      address['shop'],
      address['tourism'],
      address['amenity'],
      address['leisure'],
      address['office'],
    ]);

    if (strongPrimary.isNotEmpty) {
      final city = _readFirstNonEmpty([
        address['city'],
        address['town'],
        address['village'],
        address['municipality'],
        address['county'],
        address['state'],
      ]);

      if (city.isNotEmpty &&
          strongPrimary.toLowerCase() != city.toLowerCase()) {
        return '$strongPrimary, $city';
      }

      return strongPrimary;
    }

    final primary = _readFirstNonEmpty([
      address['road'],
      address['neighbourhood'],
      address['suburb'],
      address['city'],
      address['town'],
      address['village'],
      address['state'],
    ]);

    final city = _readFirstNonEmpty([
      address['city'],
      address['town'],
      address['village'],
      address['municipality'],
      address['county'],
      address['state'],
    ]);

    if (primary.isNotEmpty && city.isNotEmpty && primary != city) {
      return '$primary, $city';
    }

    if (displayFirst.isNotEmpty) return displayFirst;
    if (primary.isNotEmpty) return primary;

    return 'Unknown place';
  }

  String _buildNominatimSubtitle(
    Map<String, dynamic> address,
    String displayName,
  ) {
    final parts = <String>[
      _readFirstNonEmpty([
        address['suburb'],
        address['neighbourhood'],
        address['city_district'],
      ]),
      _readFirstNonEmpty([
        address['city'],
        address['town'],
        address['village'],
        address['municipality'],
      ]),
      _readFirstNonEmpty([address['state']]),
      'Malaysia',
    ].where((e) => e.isNotEmpty).toList();

    if (parts.isNotEmpty) {
      return parts.toSet().join(', ');
    }

    return displayName;
  }

  String _readFirstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  void _selectSearchResult(_SearchResultItem result) {
    setState(() {
      _selectedPoint = result.point;
      _center = result.point;
      _selectedLabel = result.title;
      _searchController.text = result.title;
      _searchResults = [];
      _resolvingTappedPlace = false;
    });

    _mapController.move(result.point, 16);
  }

  Future<void> _resolveTappedPointLabel(LatLng point) async {
    final requestToken = ++_tapResolveToken;

    setState(() {
      _resolvingTappedPlace = true;
    });

    try {
      final label = await LocationService.reverseGeocodeShortLabel(
        lat: point.latitude,
        lng: point.longitude,
      );

      debugPrint('Resolved label: $label');

      if (!mounted) return;
      if (requestToken != _tapResolveToken) return;
      if (_selectedPoint == null) return;

      final samePoint =
          _selectedPoint!.latitude == point.latitude &&
          _selectedPoint!.longitude == point.longitude;

      if (!samePoint) return;

      setState(() {
        _selectedLabel = (label != null && label.trim().isNotEmpty)
            ? label.trim()
            : "Unknown place";
        _resolvingTappedPlace = false;
      });
    } catch (e) {
      debugPrint('Tap label resolve failed: $e');

      if (!mounted) return;
      if (requestToken != _tapResolveToken) return;

      setState(() {
        _selectedLabel = "Unknown place";
        _resolvingTappedPlace = false;
      });
    }
  }

  void _handleMapTap(LatLng point) {
    setState(() {
      _selectedPoint = point;
      _selectedLabel = "Fetching location...";
      _searchResults = [];
    });

    _resolveTappedPointLabel(point);
  }

  String _fallbackLabelFromPoint(LatLng point) {
    return 'Lat ${point.latitude.toStringAsFixed(5)}, Lng ${point.longitude.toStringAsFixed(5)}';
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSearchResults = _searchResults.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Location"),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: "My location",
            onPressed: _initLocation,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              onTap: (tapPosition, point) {
                _handleMapTap(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.cleanwalk',
              ),
              if (_selectedPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedPoint!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search location in Malaysia...",
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () => _searchLocation(
                                _searchController.text,
                                showNotFoundSnack: true,
                              ),
                            ),
                    ),
                    onSubmitted: (value) => _searchLocation(
                      value,
                      showNotFoundSnack: true,
                    ),
                    onChanged: (value) {
                      _searchDebounce?.cancel();

                      if (value.trim().isEmpty) {
                        setState(() {
                          _searchResults = [];
                          _searching = false;
                        });
                        return;
                      }

                      if (value.trim().length < 4) {
                        setState(() {
                          _searchResults = [];
                          _searching = false;
                        });
                        return;
                      }

                      _searchDebounce = Timer(
                        const Duration(milliseconds: 400),
                        () => _searchLocation(
                          value,
                          showNotFoundSnack: false,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                if (!_searching && !hasSearchResults)
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withOpacity(0.92),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Search and tap one result, or tap directly on the map.",
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (hasSearchResults) ...[
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];
                          return ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                              result.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              result.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectSearchResult(result),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_loadingLocation)
            Container(
              color: Colors.white.withOpacity(0.75),
              child: const Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedLabel != null && _selectedLabel!.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedLabel!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_resolvingTappedPlace) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  "Loading place name...",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedPoint == null
                        ? null
                        : () {
                            Navigator.pop(context, {
                              'point': _selectedPoint,
                              'label': _selectedLabel ??
                                  _fallbackLabelFromPoint(_selectedPoint!),
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _selectedLabel != null
                          ? "Confirm Selected Location"
                          : "Confirm Location",
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
        ],
      ),
    );
  }
}

class _SearchResultItem {
  final String title;
  final String subtitle;
  final LatLng point;

  const _SearchResultItem({
    required this.title,
    required this.subtitle,
    required this.point,
  });
}

class _RankedSearchResult {
  final _SearchResultItem item;
  final int score;

  const _RankedSearchResult({
    required this.item,
    required this.score,
  });
}