import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(420, 180),
    minimumSize: Size(320, 140),
    center: true,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAlwaysOnTop(true);
  });
  runApp(const Elz0mbi33App());
}

class Elz0mbi33App extends StatelessWidget {
  const Elz0mbi33App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const FloatingLyricsView(),
    );
  }
}

class FloatingLyricsView extends StatefulWidget {
  const FloatingLyricsView({super.key});

  @override
  State<FloatingLyricsView> createState() => FloatingLyricsViewState();
}

class FloatingLyricsViewState extends State<FloatingLyricsView> {
  static const _clientIdKey = 'spotify_client_id';
  final _client = SpotifyLyricsClient();
  final _auth = SpotifyAuthManager();
  PlaybackState _state = const PlaybackState(status: 'Loading…');
  String? _trackId;
  Lyrics? _lyrics;
  Timer? _timer;
  bool _dragging = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final next = await _client.snapshot(auth: _auth, currentTrackId: _trackId, cachedLyrics: _lyrics);
    if (!mounted) return;
    setState(() {
      _state = next.state;
      _trackId = next.trackId;
      _lyrics = next.lyrics;
    });
  }

  Future<void> _login() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final clientIdController = TextEditingController(text: prefs.getString(_clientIdKey) ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect Spotify'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: clientIdController,
              decoration: const InputDecoration(labelText: 'Spotify Client ID'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirmed != true) return;

    final clientId = clientIdController.text.trim();
    if (clientId.isEmpty) {
      if (!mounted) return;
      setState(() => _state = const PlaybackState(status: 'Client ID required'));
      return;
    }

    await prefs.setString(_clientIdKey, clientId);
    if (!mounted) return;
    setState(() {
      _connecting = true;
      _state = const PlaybackState(status: 'Opening Spotify login…');
      _trackId = null;
      _lyrics = null;
    });

    try {
      final status = await _auth.login(clientId: clientId);
      if (!mounted) return;
      setState(() {
        _state = PlaybackState(status: status);
        _trackId = null;
        _lyrics = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = PlaybackState(status: 'Login failed: $error');
        _trackId = null;
        _lyrics = null;
      });
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _state.track == null
        ? _state.status
        : _state.lyric ?? _state.status;
    return GestureDetector(
      onPanStart: (_) => _dragging = true,
      onPanUpdate: (_) {
        if (_dragging) windowManager.startDragging();
      },
      onPanEnd: (_) => _dragging = false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xCC111111),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('elz0mbi33', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: _connecting ? null : _login,
                  child: Text(_connecting ? 'Connecting…' : 'Connect Spotify'),
                ),
                IconButton(
                  onPressed: () => windowManager.close(),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _state.track ?? _state.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                color: _state.lyric == null ? Colors.white70 : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackState {
  final String status;
  final String? track;
  final String? lyric;

  const PlaybackState({required this.status, this.track, this.lyric});
}

class PlaybackSnapshot {
  final PlaybackState state;
  final String? trackId;
  final Lyrics? lyrics;

  const PlaybackSnapshot({required this.state, this.trackId, this.lyrics});
}

class SpotifyAuthManager {
  static const _clientIdKey = 'spotify_client_id';
  static const _accessTokenKey = 'spotify_access_token';
  static const _refreshTokenKey = 'spotify_refresh_token';
  static const _expiryKey = 'spotify_access_token_expiry';
  static const _redirectUri = 'http://127.0.0.1:8888/callback';
  static const _scopes = 'user-read-playback-state user-read-currently-playing';

  Future<String> login({required String clientId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clientIdKey, clientId);

    final verifier = _randomString(96);
    final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    final state = _randomString(24);

    HttpServer? server;
    final callback = Completer<Uri>();
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888, shared: true);
    } on SocketException catch (error) {
      throw 'localhost port 8888 is busy: ${error.message}';
    }

    try {
      server.listen((request) async {
        final responseState = request.uri.queryParameters['state'];
        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];
        request.response.headers.contentType = ContentType.html;
        if (error != null && error.isNotEmpty) {
          request.response.statusCode = 400;
          request.response.write('<html><body>Spotify login failed: $error</body></html>');
          if (!callback.isCompleted) callback.completeError('Spotify login failed: $error');
        } else if (responseState == state && code != null && code.isNotEmpty) {
          request.response.write('<html><body>Spotify connected. You can close this tab.</body></html>');
          if (!callback.isCompleted) callback.complete(request.uri);
        } else {
          request.response.statusCode = 400;
          request.response.write('<html><body>Spotify login failed.</body></html>');
          if (!callback.isCompleted) callback.completeError('Spotify login failed');
        }
        await request.response.close();
      });

      final authorize = Uri.https('accounts.spotify.com', '/authorize', {
        'response_type': 'code',
        'client_id': clientId,
        'scope': _scopes,
        'redirect_uri': _redirectUri,
        'state': state,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
      });
      final launched = await launchUrl(authorize, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw 'could not open the browser';
      }

      final responseUri = await callback.future.timeout(const Duration(minutes: 3), onTimeout: () {
        throw 'timed out waiting for Spotify authorization';
      });
      final code = responseUri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw 'missing authorization code';
      }

      final tokenResponse = await http.post(
        Uri.https('accounts.spotify.com', '/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redirectUri,
          'code_verifier': verifier,
        },
      );
      if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
        throw 'token exchange failed (${tokenResponse.statusCode})';
      }

      final json = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final accessToken = json['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw 'missing access token';
      }

      await prefs.setString(_accessTokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, json['refresh_token'] as String? ?? '');
      final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
      await prefs.setInt(_expiryKey, DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch);
      return 'Spotify connected';
    } finally {
      await server.close(force: true);
    }
  }

  Future<String?> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_accessTokenKey);
    if (token == null || token.isEmpty) return null;

    final expiry = prefs.getInt(_expiryKey) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch < expiry - 30000) return token;

    final refreshToken = prefs.getString(_refreshTokenKey);
    final clientId = prefs.getString(_clientIdKey);
    if (refreshToken == null || refreshToken.isEmpty || clientId == null || clientId.isEmpty) {
      return token;
    }

    final response = await http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) return token;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final next = body['access_token'] as String?;
    if (next == null || next.isEmpty) return token;

    await prefs.setString(_accessTokenKey, next);
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    await prefs.setInt(_expiryKey, DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch);
    return next;
  }

  String _randomString(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }
}

class SpotifyLyricsClient {
  Future<PlaybackSnapshot> snapshot({
    required SpotifyAuthManager auth,
    required String? currentTrackId,
    required Lyrics? cachedLyrics,
  }) async {
    final token = await auth.accessToken();
    if (token == null || token.isEmpty) {
      return const PlaybackSnapshot(state: PlaybackState(status: 'Connect Spotify'));
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 204) {
        return const PlaybackSnapshot(state: PlaybackState(status: 'No track playing'));
      }
      if (response.statusCode == 401) {
        return const PlaybackSnapshot(state: PlaybackState(status: 'Connect Spotify'));
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const PlaybackSnapshot(state: PlaybackState(status: 'Lyrics unavailable'));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final item = data['item'] as Map<String, dynamic>?;
      if (item == null) {
        return const PlaybackSnapshot(state: PlaybackState(status: 'No track playing'));
      }

      final title = item['name'] as String? ?? '';
      final trackId = item['id'] as String?;
      final artists = (item['artists'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final artist = artists.isNotEmpty ? (artists.first['name'] as String? ?? '') : '';
      final track = '$artist — $title'.trim();
      final playing = data['is_playing'] as bool? ?? false;
      final progress = (data['progress_ms'] as num?)?.toDouble() ?? 0;
      if (trackId == null || trackId.isEmpty) {
        return PlaybackSnapshot(
          state: PlaybackState(status: playing ? 'Lyrics unavailable' : '$track (paused)', track: track),
        );
      }

      final lyrics = currentTrackId == trackId && cachedLyrics != null
          ? cachedLyrics
          : await _fetchLyrics(title: title, artist: artist);
      if (lyrics == null || lyrics.lines.isEmpty) {
        return PlaybackSnapshot(
          state: PlaybackState(status: playing ? 'Lyrics unavailable' : '$track (paused)', track: track),
          trackId: trackId,
        );
      }
      final current = lyrics.currentLine(progressMs: progress) ?? 'Loading lyrics…';
      return PlaybackSnapshot(
        state: PlaybackState(status: playing ? current : '$track (paused)', track: track, lyric: current),
        trackId: trackId,
        lyrics: lyrics,
      );
    } catch (_) {
      return const PlaybackSnapshot(state: PlaybackState(status: 'Connect Spotify'));
    }
  }

  Future<Lyrics?> _fetchLyrics({required String title, required String artist}) async {
    final uri = Uri.https('lrclib.net', '/api/get', {'track_name': title, 'artist_name': artist});
    final response = await http.get(uri, headers: {'Accept': 'application/json'});
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final synced = (json['syncedLyrics'] as String?)?.trim() ?? '';
    final plain = (json['plainLyrics'] as String?)?.trim() ?? '';
    return Lyrics.parse(synced.isNotEmpty ? synced : plain);
  }
}

class Lyrics {
  final List<LyricLine> lines;

  Lyrics(this.lines);

  factory Lyrics.parse(String text) {
    final lines = <LyricLine>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final start = raw.indexOf('[');
      final end = raw.indexOf(']');
      if (start != 0 || end <= 0) continue;
      final tag = raw.substring(1, end);
      final body = raw.substring(end + 1).trim();
      final parts = tag.split(':');
      if (parts.length != 2) continue;
      final min = double.tryParse(parts[0]);
      final sec = double.tryParse(parts[1]);
      if (min == null || sec == null || body.isEmpty) continue;
      lines.add(LyricLine((min * 60 + sec) * 1000, body));
    }
    lines.sort((a, b) => a.ms.compareTo(b.ms));
    return Lyrics(lines);
  }

  String? currentLine({required double progressMs}) {
    LyricLine? current;
    for (final line in lines) {
      if (line.ms <= progressMs) current = line;
    }
    return current?.text;
  }
}

class LyricLine {
  final double ms;
  final String text;
  LyricLine(this.ms, this.text);
}
