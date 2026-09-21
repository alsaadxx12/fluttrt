import 'package:flutter/material.dart';

import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_detail_screen.dart';
import '../../exclusive_media/data/models/exclusive_media_models.dart';
import '../../exclusive_media/presentation/screens/exclusive_details_screen.dart';
import '../data/models/asia2tv_models.dart';
import 'screens/asia2tv_details_screen.dart';

/// Opens [item] on the page that can actually play it.
///
/// A row may hold titles from more than one catalogue. One marked with
/// [Asia2TvItem.externalSourceKey] carries that catalogue's id, not a
/// Cinemana one, so the Cinemana detail page would look up an id that does
/// not exist there and show an error. It goes to its own page instead.
///
/// If the entry behind it is not in hand — nothing has listed it this run —
/// the Cinemana page is still the honest fallback: it will say it cannot
/// find the title rather than open something else.
void openCatalogueItem(BuildContext context, CinemanaItem item) {
  final nav = Navigator.of(context, rootNavigator: true);
  if (item.externalSource == Asia2TvItem.externalSourceKey) {
    final original = Asia2TvItem.byId(item.id);
    if (original != null) {
      nav.push(MaterialPageRoute(builder: (_) => Asia2TvDetailsScreen(item: original)));
      return;
    }
  } else if (item.externalSource == ExclusiveMediaItem.externalSourceKey) {
    final original = ExclusiveMediaItem.byId(item.id);
    if (original != null) {
      nav.push(MaterialPageRoute(builder: (_) => ExclusiveDetailsScreen(item: original)));
      return;
    }
  }
  nav.push(MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: item)));
}
