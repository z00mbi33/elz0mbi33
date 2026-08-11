import 'package:flutter_test/flutter_test.dart';
import 'package:elz0mbi33/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
