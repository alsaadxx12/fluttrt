import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';

/// The one heading every row on the home page hangs from.
///
/// A short brand bar, the title, and at the far end «عرض الكل» on a
/// faint red pill when the row has a page of its own. Rows used to draw
/// their own headings - some with a bar, some with an icon, some with a
/// bare red link - and read as three apps; this is the one they share.
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.onViewAll,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.fontFamily,
  });

  final String title;

  /// A display face for the heading, in place of the app's own.
  final String? fontFamily;

  /// Opens the row's own page; the pill shows only when this is set.
  final VoidCallback? onViewAll;

  /// In place of the brand bar: a live dot, say.
  final Widget? leading;

  /// After the title, before the pill.
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          leading ??
              Container(
                width: 3.5,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFF4757), Color(0xFFE50914)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          // The title takes the whole row up to the pill, so the pill sits
          // at the far end; a loose slot left its unused half after the pill.
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: fontFamily,
                color: p.text,
                fontSize: fontFamily == null ? 15 : 16,
                fontWeight: FontWeight.w900,
                letterSpacing: fontFamily == null ? -0.3 : 0,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onViewAll != null) ...[const SizedBox(width: 8), ViewAllPill(onTap: onViewAll!)],
        ],
      ),
    );
  }
}

/// «عرض الكل» on a faint red pill, with the chevron pointing on.
class ViewAllPill extends StatelessWidget {
  const ViewAllPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFE50914).withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'عرض الكل',
              style: TextStyle(color: Color(0xFFE50914), fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_left_rounded, size: 17, color: AppPalette.of(context).icon),
          ],
        ),
      ),
    );
  }
}
