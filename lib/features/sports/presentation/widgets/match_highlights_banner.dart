import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/match_highlights_screen.dart';

/// A promo card on the home page for the goals-summary section. Tapping it
/// opens the highlights page (search + yesterday's/today's matches). Phone
/// only, matching the trailers row's stance.
class MatchHighlightsBanner extends StatelessWidget {
  const MatchHighlightsBanner({super.key});

  bool get _isPhone => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    if (!_isPhone) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MatchHighlightsScreen()),
        ),
        child: Container(
          height: 172,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF00A870), Color(0xFF00C4A0), Color(0xFF0E7C63)],
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // A big soccer-ball watermark bleeding off the edge.
              Positioned(
                right: -20,
                bottom: -26,
                child: Icon(Icons.sports_soccer_rounded, size: 188, color: Colors.white.withOpacity(0.14)),
              ),
              Positioned(
                right: 96,
                top: -26,
                child: Icon(Icons.emoji_events_rounded, size: 96, color: Colors.white.withOpacity(0.10)),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Text('جديد',
                              style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.sports_soccer_rounded, color: Colors.white, size: 16),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('ملخص الأهداف',
                        style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                    const SizedBox(height: 5),
                    const Text('مباريات الأمس واليوم — ابحث وشاهد الملخّصات',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, color: Color(0xFF00A870), size: 18),
                          SizedBox(width: 4),
                          Text('شاهد الآن',
                              style: TextStyle(color: Color(0xFF0E7C63), fontSize: 12.5, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
