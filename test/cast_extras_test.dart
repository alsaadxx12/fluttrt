import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/casting/models/cast_models.dart';
import 'package:youtube_downloader/features/casting/services/cast_prefs.dart';
import 'package:youtube_downloader/features/casting/services/local_network.dart';
import 'package:youtube_downloader/features/casting/services/resume_store.dart';

void main() {
  group('which network the phone is on', () {
    test('a wifi interface with a home address is wifi', () {
      expect(
        LocalNetwork.judge({
          'rmnet_data0': ['10.42.0.7'],
          'wlan0': ['192.168.0.137'],
        }),
        LocalNetworkStatus.wifi,
      );
    });

    test('only a carrier interface is mobile data, however many bars', () {
      expect(
        LocalNetwork.judge({'rmnet_data0': ['10.42.0.7']}),
        LocalNetworkStatus.cellularOnly,
      );
      expect(LocalNetwork.advice(LocalNetworkStatus.cellularOnly), contains('بيانات الجوال'));
    });

    test('nothing up at all is offline', () {
      expect(LocalNetwork.judge({}), LocalNetworkStatus.offline);
      expect(LocalNetwork.judge({'wlan0': ['169.254.3.3']}), LocalNetworkStatus.offline);
    });

    test('an unnamed interface with a router address counts as wifi', () {
      expect(LocalNetwork.judge({'net3': ['192.168.1.20']}), LocalNetworkStatus.wifi);
    });
  });

  group('the maker behind a screen', () {
    CastDevice tv(String name, {String brand = ''}) =>
        CastDevice(id: name, name: name, brand: brand, transport: CastTransport.dlna);

    test('is read from what the set says about itself', () {
      expect(CastBrand.of(tv('Smart TV Pro', brand: 'Samsung Electronics UE55')), CastBrand.samsung);
      expect(CastBrand.of(tv('[LG] webOS TV OLED55', brand: 'LG Electronics')), CastBrand.lg);
      expect(CastBrand.of(tv('Living room', brand: 'TCL 55C645')), CastBrand.tcl);
      expect(CastBrand.of(tv('Haier TV', brand: 'Haier')), CastBrand.haier);
    });

    test('and from the name when the set says nothing', () {
      expect(CastBrand.of(tv('Hisense U7')), CastBrand.hisense);
      expect(CastBrand.of(tv('Smart TV Pro', brand: 'Microsoft Corporation Windows Media Player')),
          CastBrand.unknown);
    });
  });

  group('a softer picture for a slow link', () {
    const media = CastMedia(
      mediaId: 'm',
      title: 't',
      streamUrl: 'u1080',
      height: 1080,
      fallbacks: [
        CastStreamOption(url: 'u480', height: 480),
        CastStreamOption(url: 'u720', height: 720),
        CastStreamOption(url: 'u1080', height: 1080),
      ],
    );

    test('is the next one down, not the bottom', () {
      expect(media.softer?.height, 720);
      expect(media.copyWith(streamUrl: 'u720', height: 720).softer?.height, 480);
      expect(media.copyWith(streamUrl: 'u480', height: 480).softer, isNull);
    });

    test('copying keeps the list and the minute', () {
      final next = media.copyWith(
        streamUrl: 'u720',
        height: 720,
        position: const Duration(minutes: 12),
        quality: '720p',
      );
      expect(next.fallbacks, hasLength(3));
      expect(next.position, const Duration(minutes: 12));
      expect(next.quality, '720p');
      expect(next.mediaId, 'm');
    });
  });

  group('where a film was left', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ResumeStore.reset();
    });

    test('is remembered and read back', () async {
      await ResumeStore.save('film-1', const Duration(minutes: 40), duration: const Duration(hours: 2));
      expect(await ResumeStore.read('film-1'), const Duration(minutes: 40));
      expect(await ResumeStore.read('film-2'), isNull);
    });

    test('the first half minute is not a place to come back to', () async {
      await ResumeStore.save('film-1', const Duration(seconds: 20));
      expect(await ResumeStore.read('film-1'), isNull);
    });

    test('a film watched to the end starts over next time', () async {
      await ResumeStore.save('film-1', const Duration(minutes: 40), duration: const Duration(hours: 2));
      await ResumeStore.save('film-1', const Duration(minutes: 119), duration: const Duration(hours: 2));
      expect(await ResumeStore.read('film-1'), isNull);
    });
  });

  group('the screen used last time', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      CastPrefs.resetCache();
    });

    test('is remembered with its maker, and read back', () async {
      await CastPrefs.rememberDevice(const CastDevice(
        id: 'uuid:1',
        name: 'Smart TV Pro',
        subtitle: 'TCL',
        brand: 'TCL',
        transport: CastTransport.dlna,
      ));
      final last = await CastPrefs.lastDevice();
      expect(last?.id, 'uuid:1');
      expect(last?.brand, 'TCL');
      expect(last?.transport, CastTransport.dlna);
    });

    test('a browser is never the screen to go back to', () async {
      await CastPrefs.rememberDevice(const CastDevice(
        id: 'session',
        name: 'Chrome',
        transport: CastTransport.web,
      ));
      expect(await CastPrefs.lastDevice(), isNull);
    });

    test('a screen can be renamed, and the name taken back', () async {
      await CastPrefs.rename('uuid:1', 'تلفاز الصالة');
      expect((await CastPrefs.customNames())['uuid:1'], 'تلفاز الصالة');
      await CastPrefs.rename('uuid:1', '   ');
      expect((await CastPrefs.customNames()).containsKey('uuid:1'), isFalse);
    });
  });
}
