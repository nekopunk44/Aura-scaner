import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';

/// Точка приёма вторсырья (из OpenStreetMap / Overpass).
class _RecyclePoint {
  final LatLng pos;
  final String name;
  const _RecyclePoint(this.pos, this.name);
}

enum _MapStatus { loading, ready, denied, error }

/// Встроенная карта с ближайшими пунктами приёма вторсырья.
///
/// Данные точек — OpenStreetMap через Overpass API (бесплатно, без ключей);
/// тайлы — OSM; местоположение — geolocator. Тап по точке открывает маршрут
/// во внешнем приложении карт.
class EcoMapScreen extends StatefulWidget {
  const EcoMapScreen({super.key});

  @override
  State<EcoMapScreen> createState() => _EcoMapScreenState();
}

class _EcoMapScreenState extends State<EcoMapScreen> {
  static const _accent = Color(0xFF16A34A);
  final MapController _mapController = MapController();

  _MapStatus _status = _MapStatus.loading;
  LatLng? _userPos;
  List<_RecyclePoint> _points = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (mounted) setState(() => _status = _MapStatus.loading);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _status = _MapStatus.error);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _status = _MapStatus.denied);
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final user = LatLng(pos.latitude, pos.longitude);
      final points = await _fetchPoints(user);
      if (!mounted) return;
      setState(() {
        _userPos = user;
        _points = points;
        _status = _MapStatus.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _status = _MapStatus.error);
    }
  }

  Future<List<_RecyclePoint>> _fetchPoints(LatLng center) async {
    const radius = 6000; // метров
    final query = '[out:json][timeout:25];'
        '(node["amenity"="recycling"](around:$radius,${center.latitude},${center.longitude});'
        'node["amenity"="recycling_centre"](around:$radius,${center.latitude},${center.longitude}););'
        'out body 80;';
    try {
      final resp = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List?) ?? const [];
      final points = <_RecyclePoint>[];
      for (final e in elements) {
        if (e is! Map) continue;
        final lat = e['lat'];
        final lon = e['lon'];
        if (lat is! num || lon is! num) continue;
        final tags = e['tags'];
        final name = (tags is Map
                ? (tags['name'] ?? tags['operator'] ?? '')
                : '')
            .toString()
            .trim();
        points.add(_RecyclePoint(LatLng(lat.toDouble(), lon.toDouble()), name));
      }
      return points;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _openDirections(_RecyclePoint p) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${p.pos.latitude},${p.pos.longitude}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showPoint(AppLocalizations l10n, _RecyclePoint p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E2A3A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: _accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p.name.isNotEmpty ? p.name : l10n.ecoMapPointFallback,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openDirections(p);
                  },
                  icon: const Icon(Icons.directions, size: 18),
                  label: Text(l10n.ecoMapRoute),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.ecoMapTitle),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: switch (_status) {
        _MapStatus.loading => _info(
            const CircularProgressIndicator(color: _accent),
            l10n.ecoMapLoading,
            textColor,
          ),
        _MapStatus.denied => _message(
            Icons.location_off_outlined,
            l10n.ecoMapDenied,
            textColor,
            actionLabel: l10n.ecoMapOpenSettings,
            onAction: () => Geolocator.openAppSettings(),
          ),
        _MapStatus.error => _message(
            Icons.error_outline,
            l10n.ecoMapError,
            textColor,
            actionLabel: l10n.actionRetry,
            onAction: _init,
          ),
        _MapStatus.ready => _buildMap(l10n, isDark, textColor),
      },
    );
  }

  Widget _buildMap(AppLocalizations l10n, bool isDark, Color textColor) {
    final user = _userPos!;
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: user,
            initialZoom: 13,
            minZoom: 3,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.aura.scanner',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: user,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
                for (final p in _points)
                  Marker(
                    point: p.pos,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () => _showPoint(l10n, p),
                      child: const Icon(Icons.location_on,
                          color: _accent, size: 38),
                    ),
                  ),
              ],
            ),
            // Атрибуция OSM (требование лицензии).
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap'),
              ],
            ),
          ],
        ),

        // Плашка-счётчик / пусто.
        Positioned(
          left: 16,
          right: 16,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF1E2A3A) : Colors.white)
                  .withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(_points.isEmpty ? Icons.info_outline : Icons.recycling,
                    color: _accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _points.isEmpty
                        ? l10n.ecoMapEmpty
                        : l10n.ecoMapFoundCount(_points.length),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Кнопка «к моему местоположению».
        Positioned(
          right: 16,
          bottom: 24,
          child: FloatingActionButton(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            onPressed: () => _mapController.move(user, 14),
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Widget _info(Widget indicator, String text, Color textColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(height: 16),
          Text(text, style: TextStyle(fontSize: 14, color: textColor)),
        ],
      ),
    );
  }

  Widget _message(
    IconData icon,
    String text,
    Color textColor, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: _accent),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: textColor, height: 1.4)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
