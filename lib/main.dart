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
  final options = WindowOptions(
    size: Size(380, 160),
    minimumSize: Size(360, 150),
    center: true,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setOpacity(0.82);
    await windowManager.setAlwaysOnTop(true);
    if (Platform.isMacOS) {
      await windowManager.setVisibleOnAllWorkspaces(
        true,
        visibleOnFullScreen: true,
      );
    }
  });
  runApp(const Elz0mbi33App());
}

class Elz0mbi33App extends StatelessWidget {
  const Elz0mbi33App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(
        useMaterial3: true,
      ).copyWith(scaffoldBackgroundColor: Colors.transparent),
      home: const FloatingLyricsView(),
    );
  }
}

class FloatingLyricsView extends StatefulWidget {
  const FloatingLyricsView({super.key});

  @override
  State<FloatingLyricsView> createState() => FloatingLyricsViewState();
}

class FloatingLyricsViewState extends State<FloatingLyricsView>
    with WidgetsBindingObserver {
  static const _clientIdKey = 'spotify_client_id';
  final _client = SpotifyLyricsClient();
  final _auth = SpotifyAuthManager();
  final _clientIdController = TextEditingController();
  final _clientIdFocusNode = FocusNode();
  PlaybackState _state = const PlaybackState(status: 'Connect Spotify');
  String? _trackId;
  Lyrics? _lyrics;
  Timer? _timer;
  bool _loading = false;
  bool _refreshPending = false;
  bool _dragging = false;
  bool _connecting = false;
  bool _authChecked = false;
  bool _authenticated = false;
  bool _showLoginForm = false;
  bool _loginPendingSize = false;
  String? _loginError;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshNow());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client.onLyricsReady = _refreshNow;
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      _clientIdController.text = prefs.getString(_clientIdKey) ?? '';
    });
    _bootstrap();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _load());
  }

  Future<void> _bootstrap() async {
    final session = await _auth.accessToken();
    if (!mounted) return;
    setState(() {
      _authChecked = true;
      _authenticated = session.authenticated;
      _showLoginForm = session.needsLogin;
    });
    await _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _client.onLyricsReady = null;
    _clientIdController.dispose();
    _clientIdFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final next = await _client.snapshot(
        auth: _auth,
        currentTrackId: _trackId,
        cachedLyrics: _lyrics,
      );
      if (!mounted) return;
      setState(() {
        _state = next.state;
        _trackId = next.trackId;
        _lyrics = next.lyrics;
        if (next.needsLogin == true) {
          _authenticated = false;
          _showLoginForm = true;
          _loginError = null;
          _trackId = null;
          _lyrics = null;
        } else if (next.authenticated == true) {
          _authenticated = true;
          _showLoginForm = false;
          _loginError = null;
        }
      });
    } finally {
      _loading = false;
      if (_refreshPending && mounted) {
        _refreshPending = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _refreshNow() async {
    if (_loading) {
      _refreshPending = true;
      return;
    }
    await _load();
  }

  Future<void> _setLoginWindowSize() async {
    if (_loginPendingSize) return;
    _loginPendingSize = true;
    try {
      await windowManager.setSize(const Size(440, 248));
      await windowManager.setMinimumSize(const Size(360, 208));
    } finally {
      _loginPendingSize = false;
    }
  }

  Future<void> _setPlayerWindowSize() async {
    await windowManager.setSize(const Size(340, 140));
    await windowManager.setMinimumSize(const Size(300, 120));
  }

  Future<void> _login() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _state = const PlaybackState(status: 'Client ID required');
        _showLoginForm = true;
        _loginError = 'Client ID required';
      });
      return;
    }

    await prefs.setString(_clientIdKey, clientId);
    if (!mounted) return;
    await _setLoginWindowSize();
    setState(() {
      _connecting = true;
      _showLoginForm = true;
      _state = const PlaybackState(status: 'Opening Spotify login…');
      _loginError = null;
      _trackId = null;
      _lyrics = null;
    });

    try {
      final status = await _auth.login(clientId: clientId);
      if (!mounted) return;
      setState(() {
        _state = PlaybackState(status: status);
        _authenticated = true;
        _showLoginForm = false;
        _loginError = null;
        _trackId = null;
        _lyrics = null;
      });
      await _setPlayerWindowSize();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = PlaybackState(status: 'Login failed: $error');
        _authenticated = false;
        _showLoginForm = true;
        _loginError = '$error';
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
    final statusText = _state.track == null ? (_loginError ?? body) : body;
    final paused = _state.isPaused;
    final trackLabel = _state.track == null
        ? 'Spotify not connected'
        : _state.track!;
    final showLoginForm =
        _authChecked &&
        (_showLoginForm ||
            _state.status == 'Client ID required' ||
            _state.status == 'Opening Spotify login…' ||
            _state.status.startsWith('Login failed'));

    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = min(
            (constraints.maxWidth / 380).clamp(0.85, 1.15),
            (constraints.maxHeight / 160).clamp(0.85, 1.15),
          );
          final lyricSize = 16.0 * scale;
          final innerPadding = 10.0 * scale;
          final gap = 6.0 * scale;
          final radius = 16.0 * scale;
          final footerSize = 11.5 * scale;
          final textColor = const Color(0xFFF4EEDF);
          final mutedTextColor = const Color(0xFFD8D0C2);
          final textShadows = [
            Shadow(
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ];

          return GestureDetector(
            onPanStart: (_) => _dragging = true,
            onPanUpdate: (_) {
              if (_dragging) windowManager.startDragging();
            },
            onPanEnd: (_) => _dragging = false,
            child: Stack(
              children: [
                SizedBox.expand(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1D3A),
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: EdgeInsets.all(innerPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, lyricConstraints) {
                              final lyricTopOffset = showLoginForm
                                  ? 0.0
                                  : lyricConstraints.maxHeight * 0.2;
                              return SingleChildScrollView(
                                child: Padding(
                                  padding: EdgeInsets.only(top: lyricTopOffset),
                                  child: Align(
                                    alignment: showLoginForm
                                        ? Alignment.topLeft
                                        : Alignment.topCenter,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: showLoginForm
                                          ? CrossAxisAlignment.start
                                          : CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          statusText,
                                          maxLines: showLoginForm ? 2 : 3,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: showLoginForm
                                              ? TextAlign.start
                                              : TextAlign.center,
                                          style: TextStyle(
                                            fontSize: lyricSize,
                                            color: _state.lyric == null
                                                ? mutedTextColor
                                                : textColor,
                                            fontWeight: FontWeight.w700,
                                            decoration: TextDecoration.none,
                                            shadows: textShadows,
                                          ),
                                        ),
                                        if (paused && !showLoginForm) ...[
                                          SizedBox(height: gap),
                                          Text(
                                            'Paused',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 11.0 * scale,
                                              color: mutedTextColor,
                                              fontWeight: FontWeight.w600,
                                              decoration: TextDecoration.none,
                                              shadows: textShadows,
                                            ),
                                          ),
                                        ],
                                        if (showLoginForm) ...[
                                          SizedBox(height: gap + 4),
                                          TextField(
                                            controller: _clientIdController,
                                            focusNode: _clientIdFocusNode,
                                            autofocus: true,
                                            style: TextStyle(color: textColor),
                                            decoration: InputDecoration(
                                              labelText: 'Spotify Client ID',
                                              labelStyle: TextStyle(
                                                color: mutedTextColor,
                                              ),
                                              filled: true,
                                              fillColor: Colors.white.withValues(
                                                alpha: 0.08,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                borderSide: const BorderSide(
                                                  color: Colors.white24,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                borderSide: const BorderSide(
                                                  color: Colors.white70,
                                                ),
                                              ),
                                            ),
                                            onSubmitted: (_) =>
                                                _connecting ? null : _login(),
                                          ),
                                          SizedBox(height: gap + 2),
                                          Row(
                                            children: [
                                              TextButton(
                                                onPressed: _connecting
                                                    ? null
                                                    : () {
                                                        setState(() {
                                                          _showLoginForm =
                                                              false;
                                                          _loginError = null;
                                                          _state =
                                                              const PlaybackState(
                                                                status:
                                                                    'Connect Spotify',
                                                              );
                                                        });
                                                        _setPlayerWindowSize();
                                                      },
                                                child: Text(
                                                  'Cancel',
                                                  style: TextStyle(
                                                    color: mutedTextColor,
                                                    decoration:
                                                        TextDecoration.none,
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              FilledButton(
                                                onPressed: _connecting
                                                    ? null
                                                    : _login,
                                                child: Text(
                                                  _connecting
                                                      ? 'Connecting…'
                                                      : 'Continue',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (!showLoginForm) ...[
                          SizedBox(height: gap),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  trackLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: footerSize,
                                    fontWeight: FontWeight.w600,
                                    color: mutedTextColor,
                                    decoration: TextDecoration.none,
                                    shadows: textShadows,
                                  ),
                                ),
                              ),
                              if (_authChecked && !_authenticated) ...[
                                const SizedBox(width: 8),
                                FilledButton.tonal(
                                  onPressed: _connecting
                                      ? null
                                      : () {
                                          setState(() => _showLoginForm = true);
                                          _clientIdFocusNode.requestFocus();
                                          _setLoginWindowSize();
                                        },
                                  child: Text(
                                    _connecting ? 'Connecting…' : 'Connect',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'More options',
                        icon: const Icon(Icons.more_horiz),
                        visualDensity: VisualDensity.compact,
                        onPressed: _connecting ? null : _showOptions,
                      ),
                      if (Platform.isWindows)
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close),
                          visualDensity: VisualDensity.compact,
                          onPressed: _connecting ? null : _closeWindow,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showOptions() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.refresh),
              title: const Text('Reconnect Spotify'),
              onTap: () async {
                Navigator.of(context).pop();
                await _reconnectSpotify();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _reconnectSpotify() async {
    await _auth.clearSession();
    if (!mounted) return;
    setState(() {
      _authenticated = false;
      _showLoginForm = true;
      _loginError = null;
      _state = const PlaybackState(status: 'Connect Spotify');
      _trackId = null;
      _lyrics = null;
    });
    await _setLoginWindowSize();
    _clientIdFocusNode.requestFocus();
  }

  Future<void> _closeWindow() async {
    await windowManager.close();
  }
}

class PlaybackState {
  final String status;
  final String? track;
  final String? lyric;
  final bool? isPlaying;

  const PlaybackState({
    required this.status,
    this.track,
    this.lyric,
    this.isPlaying,
  });

  bool get isPaused => track != null && isPlaying == false;
}

class PlaybackSnapshot {
  final PlaybackState state;
  final String? trackId;
  final Lyrics? lyrics;
  final bool? needsLogin;
  final bool? authenticated;

  const PlaybackSnapshot({
    required this.state,
    this.trackId,
    this.lyrics,
    this.needsLogin,
    this.authenticated,
  });
}

class SpotifyAccessTokenResult {
  final String? token;
  final bool authenticated;
  final bool needsLogin;

  const SpotifyAccessTokenResult._(
    this.token,
    this.authenticated,
    this.needsLogin,
  );

  const SpotifyAccessTokenResult.authenticated(String token)
      : this._(token, true, false);

  const SpotifyAccessTokenResult.needsLogin()
      : this._(null, false, true);

  const SpotifyAccessTokenResult.unavailable()
      : this._(null, false, false);
}

class SpotifyAuthManager {
  static const _clientIdKey = 'spotify_client_id';
  static const _accessTokenKey = 'spotify_access_token';
  static const _refreshTokenKey = 'spotify_refresh_token';
  static const _expiryKey = 'spotify_access_token_expiry';
  static const _redirectUri = 'http://127.0.0.1:8888/callback';
  static const _scopes = 'user-read-playback-state user-read-currently-playing';
  static const _tokenTimeout = Duration(seconds: 10);

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiryKey);
  }

  Future<String> login({required String clientId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clientIdKey, clientId);

    final verifier = _randomString(96);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomString(24);

    HttpServer? server;
    final callback = Completer<Uri>();
    try {
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        8888,
        shared: true,
      );
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
          final errorDescription =
              request.uri.queryParameters['error_description'];
          final message =
              (errorDescription != null && errorDescription.isNotEmpty)
              ? '$error: $errorDescription'
              : error;
          request.response.write(
            '<html><body>Spotify login failed: $message</body></html>',
          );
          if (!callback.isCompleted) {
            callback.completeError('Spotify login failed: $message');
          }
        } else if (request.uri.path != '/callback') {
          request.response.statusCode = 404;
          request.response.write(
            '<html><body>Unexpected callback path.</body></html>',
          );
          if (!callback.isCompleted) {
            callback.completeError(
              'unexpected callback path: ${request.uri.path}',
            );
          }
        } else if (responseState == state && code != null && code.isNotEmpty) {
          request.response.write(
            '<html><body>Spotify authorization received. You can close this tab.</body></html>',
          );
          if (!callback.isCompleted) {
            callback.complete(request.uri);
          }
        } else {
          request.response.statusCode = 400;
          request.response.write(
            '<html><body>Spotify login failed.</body></html>',
          );
          if (!callback.isCompleted) {
            callback.completeError('Spotify login failed: invalid callback');
          }
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
      final launched = await launchUrl(
        authorize,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw 'could not open the browser';
      }

      final responseUri = await callback.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          throw 'timed out waiting for Spotify authorization';
        },
      );
      final code = responseUri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw 'missing authorization code';
      }

      final tokenResponse = await http
          .post(
        Uri.https('accounts.spotify.com', '/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redirectUri,
          'code_verifier': verifier,
        },
      )
          .timeout(_tokenTimeout);
      if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
        throw 'token exchange failed (${tokenResponse.statusCode}): ${tokenResponse.body}';
      }

      final json = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final accessToken = json['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw 'missing access token';
      }

      await prefs.setString(_accessTokenKey, accessToken);
      final refreshToken = json['refresh_token'] as String?;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }
      final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
      await prefs.setInt(
        _expiryKey,
        DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch,
      );
      return 'Spotify connected';
    } finally {
      await server.close(force: true);
    }
  }

  Future<SpotifyAccessTokenResult> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_accessTokenKey);
    if (token != null && token.isNotEmpty) {
      final expiry = prefs.getInt(_expiryKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch < expiry - 30000) {
        return SpotifyAccessTokenResult.authenticated(token);
      }
    }

    final clientId = prefs.getString(_clientIdKey);
    final refreshToken = prefs.getString(_refreshTokenKey);
    if (refreshToken == null ||
        refreshToken.isEmpty ||
        clientId == null ||
        clientId.isEmpty) {
      await clearSession();
      return const SpotifyAccessTokenResult.needsLogin();
    }

    try {
      final response = await http
          .post(
        Uri.https('accounts.spotify.com', '/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      )
          .timeout(_tokenTimeout);
      if (response.statusCode == 400 || response.statusCode == 401) {
        await clearSession();
        return const SpotifyAccessTokenResult.needsLogin();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const SpotifyAccessTokenResult.unavailable();
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final next = body['access_token'] as String?;
      if (next == null || next.isEmpty) {
        return const SpotifyAccessTokenResult.unavailable();
      }

      await prefs.setString(_accessTokenKey, next);
      final rotatedRefreshToken = body['refresh_token'] as String?;
      if (rotatedRefreshToken != null && rotatedRefreshToken.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, rotatedRefreshToken);
      }
      final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
      await prefs.setInt(
        _expiryKey,
        DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch,
      );
      return SpotifyAccessTokenResult.authenticated(next);
    } on TimeoutException {
      return const SpotifyAccessTokenResult.unavailable();
    } on SocketException {
      return const SpotifyAccessTokenResult.unavailable();
    } on http.ClientException {
      return const SpotifyAccessTokenResult.unavailable();
    }
  }

  String _randomString(int length) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}

class SpotifyLyricsClient {
  final Map<String, Lyrics> _lyricsCache = {};
  final Set<String> _loadingTracks = {};
  final Map<String, int> _lyricsFailures = {};
  final Map<String, DateTime> _nextLyricsRetry = {};
  VoidCallback? onLyricsReady;
  final _rateLimiter = LRCLIBRateLimiter();
  static const _maxLyricsFailures = 3;
  static const _lyricsRetryDelay = Duration(seconds: 15);
  static const _spotifyTimeout = Duration(seconds: 8);

  Future<PlaybackSnapshot> snapshot({
    required SpotifyAuthManager auth,
    required String? currentTrackId,
    required Lyrics? cachedLyrics,
  }) async {
    final session = await auth.accessToken();
    if (session.needsLogin) {
      return const PlaybackSnapshot(
        state: PlaybackState(status: 'Connect Spotify'),
        needsLogin: true,
        authenticated: false,
      );
    }
    final token = session.token;
    if (token == null || token.isEmpty) {
      return const PlaybackSnapshot(
        state: PlaybackState(status: 'Spotify unavailable'),
        authenticated: false,
      );
    }

    try {
      final response = await http
          .get(
        Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
        headers: {'Authorization': 'Bearer $token'},
      )
          .timeout(_spotifyTimeout);
      if (response.statusCode == 204) {
        return const PlaybackSnapshot(
          state: PlaybackState(status: 'No track playing'),
          needsLogin: false,
          authenticated: true,
        );
      }
      if (response.statusCode == 401) {
        await auth.clearSession();
        return const PlaybackSnapshot(
          state: PlaybackState(status: 'Connect Spotify'),
          needsLogin: true,
          authenticated: false,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const PlaybackSnapshot(
          state: PlaybackState(status: 'Lyrics unavailable'),
          needsLogin: false,
          authenticated: true,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final item = data['item'] as Map<String, dynamic>?;
      if (item == null) {
        return const PlaybackSnapshot(
          state: PlaybackState(status: 'No track playing'),
          needsLogin: false,
          authenticated: true,
        );
      }

      final title = item['name'] as String? ?? '';
      final trackId = item['id'] as String?;
      final artists =
          (item['artists'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final artist = artists.isNotEmpty
          ? (artists.first['name'] as String? ?? '')
          : '';
      final track = '$artist — $title'.trim();
      final playing = data['is_playing'] as bool? ?? false;
      final progress = (data['progress_ms'] as num?)?.toDouble() ?? 0;
      if (trackId == null || trackId.isEmpty) {
        return PlaybackSnapshot(
          state: PlaybackState(
            status: 'Lyrics unavailable',
            track: track,
            isPlaying: playing,
          ),
          needsLogin: false,
          authenticated: true,
        );
      }

      final lyrics = currentTrackId == trackId && cachedLyrics != null
          ? cachedLyrics
          : _lyricsCache[trackId];
      if (lyrics != null && lyrics.lines.isNotEmpty) {
        _clearLyricsRetryState(trackId);
        final current =
            lyrics.currentLine(progressMs: progress) ?? 'Loading lyrics…';
        return PlaybackSnapshot(
          state: PlaybackState(
            status: current,
            track: track,
            lyric: current,
            isPlaying: playing,
          ),
          trackId: trackId,
          lyrics: lyrics,
        );
      }

      final failures = _lyricsFailures[trackId] ?? 0;
      final nextRetryAt = _nextLyricsRetry[trackId];
      if (failures >= _maxLyricsFailures &&
          nextRetryAt != null &&
          DateTime.now().isBefore(nextRetryAt)) {
        return PlaybackSnapshot(
          state: PlaybackState(
            status: 'No lyrics available',
            track: track,
            isPlaying: playing,
          ),
          trackId: trackId,
          needsLogin: false,
          authenticated: true,
        );
      }

      if (_loadingTracks.add(trackId)) {
        unawaited(_primeLyrics(trackId: trackId, title: title, artist: artist));
      }

      return PlaybackSnapshot(
        state: PlaybackState(
          status: 'Loading lyrics…',
          track: track,
          isPlaying: playing,
        ),
        trackId: trackId,
        needsLogin: false,
        authenticated: true,
      );
    } on TimeoutException {
      return const PlaybackSnapshot(
        state: PlaybackState(status: 'Spotify unavailable'),
        authenticated: false,
      );
    } on SocketException {
      return const PlaybackSnapshot(
        state: PlaybackState(status: 'Spotify unavailable'),
        authenticated: false,
      );
    } on http.ClientException {
      return const PlaybackSnapshot(
        state: PlaybackState(status: 'Spotify unavailable'),
        authenticated: false,
      );
    } catch (_) {
      return const PlaybackSnapshot(
        state: PlaybackState(status: 'Spotify unavailable'),
        authenticated: false,
      );
    }
  }

  Future<void> _primeLyrics({
    required String trackId,
    required String title,
    required String artist,
  }) async {
    try {
      final lyrics = await _fetchLyrics(title: title, artist: artist);
      if (lyrics != null && lyrics.lines.isNotEmpty) {
        _lyricsCache[trackId] = lyrics;
        _clearLyricsRetryState(trackId);
        onLyricsReady?.call();
      } else {
        _recordLyricsFailure(trackId);
      }
    } finally {
      _loadingTracks.remove(trackId);
    }
  }

  void _clearLyricsRetryState(String trackId) {
    _lyricsFailures.remove(trackId);
    _nextLyricsRetry.remove(trackId);
  }

  void _recordLyricsFailure(String trackId) {
    final failures = (_lyricsFailures[trackId] ?? 0) + 1;
    _lyricsFailures[trackId] = failures;
    if (failures >= _maxLyricsFailures) {
      _nextLyricsRetry[trackId] = DateTime.now().add(_lyricsRetryDelay);
      onLyricsReady?.call();
    }
  }

  Future<Lyrics?> _fetchLyrics({
    required String title,
    required String artist,
  }) async {
    final get = await _fetchLyricsEndpoint(
      '/api/get',
      title: title,
      artist: artist,
    );
    if (get != null) return get;
    return _fetchLyricsEndpoint('/api/search', title: title, artist: artist);
  }

  Future<Lyrics?> _fetchLyricsEndpoint(
    String path, {
    required String title,
    required String artist,
  }) async {
    await _rateLimiter.acquire();
    final uri = Uri.https('lrclib.net', path, {
      'track_name': title,
      'artist_name': artist,
    });
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return _lyricsFromMap(decoded);
    }
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final lyrics = _lyricsFromMap(item);
          if (lyrics != null && lyrics.lines.isNotEmpty) return lyrics;
        }
      }
    }
    return null;
  }

  Lyrics? _lyricsFromMap(Map<String, dynamic> json) {
    final synced = (json['syncedLyrics'] as String?)?.trim() ?? '';
    final plain = (json['plainLyrics'] as String?)?.trim() ?? '';
    if (synced.isEmpty && plain.isEmpty) return null;
    return Lyrics.parse(synced.isNotEmpty ? synced : plain);
  }
}

class LRCLIBRateLimiter {
  DateTime _nextAllowedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> acquire() async {
    final wait = _nextAllowedAt.difference(DateTime.now());
    if (wait > Duration.zero) {
      await Future.delayed(wait);
    }
    _nextAllowedAt = DateTime.now().add(const Duration(milliseconds: 300));
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
