import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Reads a stretch of the source, `from`..`to` inclusive, from the CDN.
typedef SourceFetch = Future<Uint8List> Function(int from, int to);

/// The film, on the phone's storage, filling in as it is fetched.
///
/// A television that is served through the phone used to be served straight
/// through it: every byte came from the CDN the moment the set asked, and a
/// seek was a fresh trip to the internet for a stretch the phone might have
/// carried a minute ago. On a slow connection that is a set that waits at
/// every seek, and a film watched twice is a film downloaded twice.
///
/// This keeps what has been fetched in a file, in chunks, with a map of
/// which chunks are there. A read that lands on chunks already fetched is
/// answered from the file — a seek back is instant, a second viewing needs
/// no internet at all — and a read that lands on chunks not yet fetched
/// fetches exactly those and keeps them. Alongside, [prefetch] walks ahead
/// of the set on its own, so that by the time the set asks for the next
/// stretch it is usually already here: the wifi carries the film once and
/// the internet link is used as fully as it can be, whatever the set's own
/// pace.
///
/// One file per film, named by its address, so the next evening's viewing
/// of the same film picks up the same file.
class SourceCache {
  SourceCache._(this.key, this.total, this._data, this._mapFile, this._have);

  /// Fetched and kept in stretches of this size. Half a megabyte: a seek
  /// fetches at most one wasted half-chunk on each side, and a
  /// two-gigabyte film's map is four thousand bytes.
  static const int chunk = 512 * 1024;

  /// How much a prefetch asks the CDN for at a time.
  ///
  /// One chunk. A read on the set's behalf that lands on a run in flight
  /// waits for the whole run, and in the first seconds of a film - when
  /// the set is filling its buffer as fast as the link allows - every
  /// half-megabyte of waiting is half a megabyte longer before the
  /// picture. One request per chunk costs a little per request on a fast
  /// link and nothing that matters on a slow one.
  static const int _prefetchRun = chunk;

  /// What the whole cache directory may hold. Films that would push it
  /// over are the oldest ones to go.
  static const int _budget = 3 * 1024 * 1024 * 1024;

  /// A film untouched for this long is not coming back.
  static const Duration _keepFor = Duration(days: 7);

  final String key;
  final int total;
  final RandomAccessFile _data;
  final File _mapFile;

  /// One byte per chunk: 1 when the chunk is in the file.
  final Uint8List _have;

  /// Fetches in flight, by first chunk, so two readers wanting the same
  /// stretch make one trip.
  final Map<int, Future<void>> _inflight = <int, Future<void>>{};

  /// Reads waiting on the set's behalf. The prefetcher stands aside while
  /// this is above zero: the set's own request is the one that must not
  /// wait.
  int _demand = 0;

  /// Where the set last read. The prefetcher works forward from here.
  int _playhead = 0;

  bool _prefetching = false;
  bool _closed = false;

  /// True once the set has read something. The prefetch waits for it:
  /// until then there is no playhead to work forward from, and a run
  /// started before the set's first request would be the one thing that
  /// request had to wait for.
  bool _everRead = false;

  /// The file operations, one at a time: a RandomAccessFile refuses a
  /// second operation while one is pending.
  Future<void> _lock = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() run) {
    final done = _lock.then((_) => run());
    _lock = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  /// The name a source is kept under: its host and path, without the
  /// query — a signed url's signature changes between visits, the film
  /// behind it does not.
  static String keyFor(String url) {
    final uri = Uri.tryParse(url);
    final name = uri == null ? url : '${uri.host}:${uri.port}${uri.path}';
    return sha1.convert(utf8.encode(name)).toString();
  }

  /// Opens, or reopens, the cache for a source of [total] bytes in [dir].
  ///
  /// A file left from an earlier viewing is picked up with whatever it
  /// holds — unless the source has changed length, in which case it is
  /// not the same film and is started over.
  static Future<SourceCache?> open(Directory dir, String url, int total) async {
    if (total <= 0) return null;
    try {
      await dir.create(recursive: true);
      final key = keyFor(url);
      final dataFile = File('${dir.path}${Platform.pathSeparator}$key.part');
      final mapFile = File('${dir.path}${Platform.pathSeparator}$key.map');
      final chunks = (total + chunk - 1) ~/ chunk;

      Uint8List have;
      if (await mapFile.exists() && await dataFile.exists()) {
        final bytes = await mapFile.readAsBytes();
        // The map is the chunk flags after eight bytes of total length;
        // one that describes another length describes another film.
        final data = ByteData.sublistView(bytes);
        if (bytes.length == 8 + chunks && data.getUint64(0) == total) {
          have = Uint8List.sublistView(bytes, 8);
        } else {
          have = Uint8List(chunks);
        }
      } else {
        have = Uint8List(chunks);
      }
      final raf = await dataFile.open(mode: FileMode.append);
      // Touched, so the pruning below knows this one is in use.
      await dataFile.setLastModified(DateTime.now());
      final cache = SourceCache._(key, total, raf, mapFile, have);
      await cache._saveMap();
      debugPrint('[cast] cache $key: ${cache.fetchedBytes ~/ 1048576} of '
          '${total ~/ 1048576} MB already here');
      return cache;
    } catch (e) {
      debugPrint('[cast] cache could not be opened: $e');
      return null;
    }
  }

  /// How much of the film is here.
  int get fetchedBytes {
    var n = 0;
    for (var i = 0; i < _have.length; i++) {
      if (_have[i] == 0) continue;
      n += i == _have.length - 1 ? total - i * chunk : chunk;
    }
    return n;
  }

  bool get isComplete {
    for (final flag in _have) {
      if (flag == 0) return false;
    }
    return true;
  }

  /// True when every byte of `from`..`to` is already in the file.
  bool has(int from, int to) {
    for (var c = from ~/ chunk; c <= to ~/ chunk; c++) {
      if (_have[c] == 0) return false;
    }
    return true;
  }

  /// `from`..`to` inclusive, from the file — fetching first whatever of it
  /// is not there yet.
  ///
  /// On the set's behalf unless [planning]: a read made while the film is
  /// being planned - its index, its first bytes - does not move the
  /// playhead and does not start the prefetch, which waits for the set's
  /// own first request.
  Future<Uint8List> read(
    int from,
    int to,
    SourceFetch fetch, {
    bool Function()? abandoned,
    bool planning = false,
  }) async {
    if (!planning) {
      _playhead = to + 1;
      _everRead = true;
    }
    _demand++;
    try {
      await _ensure(from, to, fetch, abandoned: abandoned);
    } finally {
      _demand--;
    }
    return _locked(() async {
      await _data.setPosition(from);
      return _data.read(to - from + 1);
    });
  }

  /// Sees to it that every chunk covering `from`..`to` is in the file.
  Future<void> _ensure(
    int from,
    int to,
    SourceFetch fetch, {
    bool Function()? abandoned,
  }) async {
    final first = from ~/ chunk;
    final last = to ~/ chunk;
    var c = first;
    while (c <= last) {
      if (_have[c] != 0) {
        c++;
        continue;
      }
      final pending = _inflight[c];
      if (pending != null) {
        await pending;
        continue;
      }
      // A run of missing chunks, fetched as one request.
      var end = c;
      while (end + 1 <= last && _have[end + 1] == 0 && !_inflight.containsKey(end + 1)) {
        end++;
      }
      await _fetchChunks(c, end, fetch, abandoned: abandoned);
      c = end + 1;
    }
  }

  Future<void> _fetchChunks(
    int first,
    int last,
    SourceFetch fetch, {
    bool Function()? abandoned,
  }) {
    final done = () async {
      final from = first * chunk;
      final to = ((last + 1) * chunk - 1).clamp(0, total - 1);
      final bytes = await fetch(from, to);
      if (_closed) return;
      if (bytes.length != to - from + 1) {
        throw HttpException('cdn sent ${bytes.length} of ${to - from + 1} bytes');
      }
      await _locked(() async {
        await _data.setPosition(from);
        await _data.writeFrom(bytes);
      });
      for (var c = first; c <= last; c++) {
        _have[c] = 1;
      }
      await _saveMap();
    }();
    for (var c = first; c <= last; c++) {
      _inflight[c] = done;
    }
    return done.whenComplete(() {
      for (var c = first; c <= last; c++) {
        _inflight.remove(c);
      }
    });
  }

  Future<void> _saveMap() async {
    if (_closed) return;
    try {
      final out = Uint8List(8 + _have.length);
      ByteData.sublistView(out).setUint64(0, total);
      out.setRange(8, out.length, _have);
      await _mapFile.writeAsBytes(out, flush: true);
    } catch (e) {
      debugPrint('[cast] cache map: $e');
    }
  }

  /// Fetches the rest of the film on its own, forward from where the set
  /// is reading, then whatever is left behind it.
  ///
  /// Runs until the film is complete or [close] is called. Stands aside
  /// whenever the set itself is waiting on a read, so the prefetch never
  /// costs the set a stall — it only fills the quiet moments, which on a
  /// slow link is most of them.
  void prefetch(SourceFetch fetch) {
    if (_prefetching || _closed) return;
    _prefetching = true;
    unawaited(_prefetchLoop(fetch));
  }

  Future<void> _prefetchLoop(SourceFetch fetch) async {
    try {
      var failures = 0;
      while (!_closed) {
        if (!_everRead || _demand > 0 || _inflight.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final next = _nextMissing(_playhead ~/ chunk);
        if (next < 0) {
          debugPrint('[cast] cache $key: the whole film is here');
          return;
        }
        var end = next;
        while (end + 1 < _have.length &&
            _have[end + 1] == 0 &&
            (end + 1 - next + 1) * chunk <= _prefetchRun) {
          end++;
        }
        try {
          await _fetchChunks(next, end, fetch);
          failures = 0;
        } catch (e) {
          if (_closed) return;
          // The link is down, or the CDN is. Wait, longer each time, and
          // try again: the set's own reads are still answered meanwhile.
          failures++;
          debugPrint('[cast] prefetch ($failures): $e');
          if (failures >= 8) return;
          await Future<void>.delayed(Duration(seconds: 2 * failures));
        }
      }
    } finally {
      _prefetching = false;
    }
  }

  /// The first chunk not yet here, at or after [start], wrapping round to
  /// the beginning. -1 when there is none.
  int _nextMissing(int start) {
    final n = _have.length;
    for (var i = 0; i < n; i++) {
      final c = (start + i) % n;
      if (_have[c] == 0) return c;
    }
    return -1;
  }

  /// Stops the prefetch and lets go of the file. What was fetched stays.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _locked(() => _data.close());
    } catch (_) {}
  }

  /// Keeps the cache directory within its budget: films untouched for a
  /// week go first, then the oldest, until what is left fits.
  static Future<void> prune(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      final parts = <File>[];
      await for (final entry in dir.list()) {
        if (entry is File && entry.path.endsWith('.part')) parts.add(entry);
      }
      final now = DateTime.now();
      final dated = <(File, DateTime, int)>[];
      for (final part in parts) {
        final stat = await part.stat();
        dated.add((part, stat.modified, stat.size));
      }
      dated.sort((a, b) => a.$2.compareTo(b.$2));
      var held = dated.fold<int>(0, (n, d) => n + d.$3);
      for (final (part, modified, size) in dated) {
        final stale = now.difference(modified) > _keepFor;
        if (!stale && held <= _budget) break;
        try {
          await part.delete();
          final map = File(part.path.replaceAll(RegExp(r'\.part$'), '.map'));
          if (await map.exists()) await map.delete();
          held -= size;
          debugPrint('[cast] cache: dropped ${part.uri.pathSegments.last} '
              '(${size ~/ 1048576} MB, ${stale ? "stale" : "over budget"})');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[cast] cache prune: $e');
    }
  }
}
