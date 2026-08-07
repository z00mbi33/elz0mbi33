import 'package:flutter_test/flutter_test.dart';
import 'package:elz0mbi33/main.dart';

void main() {
  test('paused state only depends on playback flag', () {
    expect(const PlaybackState(status: 'x', track: 't', isPlaying: false).isPaused, isTrue);
    expect(const PlaybackState(status: 'x', track: 't', isPlaying: true).isPaused, isFalse);
    expect(const PlaybackState(status: 'x').isPaused, isFalse);
  });
}
