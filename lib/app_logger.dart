import 'dart:async';
import 'dart:io';

class AppLogger {
  AppLogger._(this._file);

  final File _file;
  Future<void> _queue = Future.value();

  String get path => _file.path;

  static Future<AppLogger> create({String? path}) async {
    final resolvedPath = path ?? await _defaultPath();
    final logger = AppLogger._(File(resolvedPath));
    await logger._file.parent.create(recursive: true);
    await logger._file.writeAsString('', mode: FileMode.append, flush: true);
    return logger;
  }

  Future<void> debug(String category, String message, {Object? error, StackTrace? stackTrace}) =>
      _write('DEBUG', category, message, error: error, stackTrace: stackTrace);

  Future<void> info(String category, String message, {Object? error, StackTrace? stackTrace}) =>
      _write('INFO', category, message, error: error, stackTrace: stackTrace);

  Future<void> warning(String category, String message, {Object? error, StackTrace? stackTrace}) =>
      _write('WARN', category, message, error: error, stackTrace: stackTrace);

  Future<void> error(String category, String message, {Object? error, StackTrace? stackTrace}) =>
      _write('ERROR', category, message, error: error, stackTrace: stackTrace);

  Future<void> _write(
    String level,
    String category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final line = _formatLine(level, category, message, error: error, stackTrace: stackTrace);
    _queue = _queue.then((_) async {
      try {
        await _rotateIfNeeded();
        await _file.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (_) {
        // Best effort only.
      }
    });
    return _queue;
  }

  Future<void> _rotateIfNeeded() async {
    try {
      if (!await _file.exists()) {
        return;
      }
      final stat = await _file.stat();
      if (stat.size < 1024 * 1024) {
        return;
      }
      final backup = File('${_file.path}.1');
      if (await backup.exists()) {
        await backup.delete();
      }
      await _file.copy(backup.path);
      await _file.writeAsString('', mode: FileMode.write, flush: true);
    } catch (_) {
      // Best effort only.
    }
  }

  String _formatLine(
    String level,
    String category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer('$timestamp [$level] $category: ${_redact(message)}');
    if (error != null) {
      buffer.write(' | error=${_redact(error.toString())}');
    }
    if (stackTrace != null) {
      buffer.write('\n${_redact(stackTrace.toString())}');
    }
    buffer.write('\n');
    return buffer.toString();
  }

  String _redact(String input) {
    var value = input;
    final replacements = <RegExp, String>{
      RegExp(r'Bearer\s+[A-Za-z0-9._~\-]+', caseSensitive: false): 'Bearer [redacted]',
      RegExp(
        r'(access_token|refresh_token|client_secret|code_verifier|authorization)\s*[:=]\s*[^,\s\"]+',
        caseSensitive: false,
      ): r'$1=[redacted]',
      RegExp(
        r'"(access_token|refresh_token|client_secret|code_verifier|authorization)"\s*:\s*"[^"]*"',
        caseSensitive: false,
      ): r'"$1":"[redacted]"',
    };
    for (final entry in replacements.entries) {
      value = value.replaceAllMapped(entry.key, (match) => entry.value == r'$1=[redacted]'
          ? '${match.group(1)}=[redacted]'
          : entry.value == r'"$1":"[redacted]"'
              ? '"${match.group(1)}":"[redacted]"'
              : entry.value);
    }
    return value;
  }

  static Future<String> _defaultPath() async {
    final primary = File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}elz0mbi33.log');
    if (await _canWrite(primary)) {
      return primary.path;
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base = localAppData == null || localAppData.isEmpty
        ? Directory.systemTemp
        : Directory(localAppData);
    final fallback = File('${base.path}${Platform.pathSeparator}elz0mbi33${Platform.pathSeparator}logs${Platform.pathSeparator}elz0mbi33.log');
    await fallback.parent.create(recursive: true);
    return fallback.path;
  }

  static Future<bool> _canWrite(File file) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString('', mode: FileMode.append, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
