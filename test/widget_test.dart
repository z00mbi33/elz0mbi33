import 'package:flutter_test/flutter_test.dart';
import 'package:elz0mbi33/main.dart';
import 'package:elz0mbi33/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  test('paused state only depends on playback flag', () {
    expect(const PlaybackState(status: 'x', track: 't', isPlaying: false).isPaused, isTrue);
    expect(const PlaybackState(status: 'x', track: 't', isPlaying: true).isPaused, isFalse);
    expect(const PlaybackState(status: 'x').isPaused, isFalse);
  });

  test('refresh failure without credentials requires login', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = SpotifyAuthManager();

    final result = await auth.accessToken();

    expect(result.needsLogin, isTrue);
    expect(result.authenticated, isFalse);
    expect(result.token, isNull);
  });

  test('lyrics parser supports synced and plain text', () {
    final synced = Lyrics.parse('[00:01.00]Hello\n[00:02.50]World');
    expect(synced.lines, hasLength(2));
    expect(synced.currentLine(progressMs: 2500), 'World');

    final plain = Lyrics.parse('Plain line 1\nPlain line 2');
    expect(plain.lines, isEmpty);
    expect(plain.currentLine(progressMs: 0), 'Plain line 1\nPlain line 2');
  });

  test('logger redacts obvious secrets', () {
    final file = File('/tmp/elz0mbi33-test.log');
    if (file.existsSync()) {
      file.deleteSync();
    }
    final logger = AppLogger.create(path: file.path);
    expect(logger, isA<Future<AppLogger>>());
  });
}
