import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shahid_providers.dart';
import 'shahid_widgets.dart';

/// Every live channel on MBC Shahid, filterable by free / genre.
class ShahidChannelsScreen extends ConsumerStatefulWidget {
  const ShahidChannelsScreen({super.key});

  @override
  ConsumerState<ShahidChannelsScreen> createState() => _ShahidChannelsScreenState();
}

class _ShahidChannelsScreenState extends ConsumerState<ShahidChannelsScreen> {
  String _filter = kShahidFilterAll;

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(shahidChannelsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D111A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'القنوات المباشرة',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(shahidChannelsProvider),
          ),
        ],
      ),
      body: channelsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFE50914)),
        ),
        error: (_, __) => _message('تعذّر تحميل القنوات'),
        data: (channels) {
          if (channels.isEmpty) return _message('لا توجد قنوات حالياً');
          final filters = shahidChannelFilters(channels);
          final selected = filters.contains(_filter) ? _filter : kShahidFilterAll;
          final visible = filterShahidChannels(channels, selected);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Text(
                  '${channels.length} قناة مجانية من MBC شاهد',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5),
                ),
              ),
              ShahidFilterChips(
                filters: filters,
                selected: selected,
                onSelected: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visible.isEmpty
                    ? _message('لا توجد قنوات في هذا التصنيف')
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.7,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (_, i) => LayoutBuilder(
                          builder: (context, c) =>
                              ShahidChannelCard(
                                channel: visible[i],
                                channels: channels,
                                width: c.maxWidth,
                              ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tv_off_rounded, size: 44, color: Colors.white24),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: Colors.white60, fontSize: 14)),
          ],
        ),
      );
}
