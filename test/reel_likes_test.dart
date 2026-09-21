import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reel_likes_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a toggled like is remembered and comes back after a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ReelLikesNotifier();
    await a.ready;
    expect(a.isLiked('v1'), isFalse);

    await a.toggle('v1');
    expect(a.isLiked('v1'), isTrue);
    expect(a.state, {'v1'});

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(ReelLikesNotifier.key), ['v1']);

    // A fresh notifier (a new launch) reads the same store.
    final b = ReelLikesNotifier();
    await b.ready;
    expect(b.isLiked('v1'), isTrue);
    a.dispose();
    b.dispose();
  });

  test('toggling again takes the like back and clears it from the store', () async {
    SharedPreferences.setMockInitialValues({
      ReelLikesNotifier.key: ['v1', 'v2'],
    });
    final n = ReelLikesNotifier();
    await n.ready;
    expect(n.state, {'v1', 'v2'});

    await n.toggle('v1');
    expect(n.state, {'v2'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(ReelLikesNotifier.key), ['v2']);
    n.dispose();
  });

  test('like() only ever adds — a double tap never un-likes', () async {
    SharedPreferences.setMockInitialValues({});
    final n = ReelLikesNotifier();
    await n.like('v9');
    await n.like('v9');
    expect(n.state, {'v9'});
    await n.like('');
    expect(n.state, {'v9'});
    n.dispose();
  });

  test('an early toggle waits for the saved set instead of overwriting it', () async {
    SharedPreferences.setMockInitialValues({
      ReelLikesNotifier.key: ['saved'],
    });
    final n = ReelLikesNotifier();
    // No `await n.ready` here: the toggle itself must wait.
    await n.toggle('new');
    expect(n.state, {'saved', 'new'});
    n.dispose();
  });
}
