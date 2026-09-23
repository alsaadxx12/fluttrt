import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/services/sports_service.dart';

/// Iraq v Oman was shown with Senegal's line-up: the 365scores search had
/// handed back an unrelated game and it was taken on trust. Now a game is
/// used only when both its teams are the teams that were asked about.
void main() {
  test('the same two teams agree, whatever the prefix or the order', () {
    expect(SportsService.teamsAgree('العراق', 'عمان', 'منتخب العراق', 'منتخب عمان'), isTrue);
    expect(SportsService.teamsAgree('Iraq', 'Oman', 'Oman', 'Iraq'), isTrue);
    expect(SportsService.teamsAgree('Al Hilal FC', 'Al Nassr', 'Hilal', 'Nassr'), isTrue);
  });

  test('a game with neither team is refused', () {
    expect(SportsService.teamsAgree('العراق', 'عمان', 'السنغال', 'الكاميرون'), isFalse);
    expect(SportsService.teamsAgree('Iraq', 'Oman', 'Senegal', 'Cameroon'), isFalse);
  });

  test('one team is enough: the other side is often named in another language', () {
    expect(SportsService.teamsAgree('Iraq', 'عمان', 'Iraq', 'Oman'), isTrue);
  });
}
