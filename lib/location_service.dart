import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LocationService {
  static Future<String?> reverseGeocodeShortLabel({
    required double lat,
    required double lng,
  }) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2'
        '&lat=$lat'
        '&lon=$lng'
        '&addressdetails=1'
        '&zoom=18',
      );

      debugPrint('Reverse geocode URL: $url');

      final res = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'CleanWalk-FYP/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('Reverse geocode status: ${res.statusCode}');
      debugPrint('Reverse geocode body: ${res.body}');

      if (res.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final address = (data['address'] as Map?)?.cast<String, dynamic>();

      final name = _firstNonEmpty([
        data['name'],
      ]);

      final road = _firstNonEmpty([
        address?['road'],
        address?['pedestrian'],
        address?['footway'],
        address?['residential'],
      ]);

      final area = _firstNonEmpty([
        address?['neighbourhood'],
        address?['suburb'],
        address?['quarter'],
        address?['city_district'],
        address?['district'],
      ]);

      final city = _firstNonEmpty([
        address?['city'],
        address?['town'],
        address?['municipality'],
        address?['county'],
        address?['state'],
      ]);

      if (_isNotEmpty(name) && _isNotEmpty(city)) {
        return '${name!}, ${city!}';
      }

      if (_isNotEmpty(road) && _isNotEmpty(city)) {
        return '${road!}, ${city!}';
      }

      if (_isNotEmpty(area) && _isNotEmpty(city)) {
        return '${area!}, ${city!}';
      }

      if (_isNotEmpty(road)) return road;
      if (_isNotEmpty(area)) return area;
      if (_isNotEmpty(city)) return city;

      final displayName = data['display_name'];
      if (displayName is String && displayName.trim().isNotEmpty) {
        final parts = displayName
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        if (parts.length >= 2) {
          return '${parts[0]}, ${parts[1]}';
        }
        return displayName.trim();
      }

      return null;
    } on TimeoutException catch (e) {
      debugPrint('Reverse geocode timeout: $e');
      return null;
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
      return null;
    }
  }

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static bool _isNotEmpty(String? s) => s != null && s.trim().isNotEmpty;
}