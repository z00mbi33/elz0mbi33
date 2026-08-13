import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class LogViewerApp extends StatelessWidget {
  const LogViewerApp({super.key, required this.logPath});

  final String logPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: LogViewerView(logPath: logPath),
    );
  }
}

class LogViewerView extends StatefulWidget {
  const LogViewerView({super.key, required this.logPath});

  final String logPath;

  @override
  State<LogViewerView> createState() => _LogViewerViewState();
}

class _LogViewerViewState extends State<LogViewerView> {
  final _scrollController = ScrollController();
  Timer? _timer;
  String _content = 'Loading logs…';
  bool _followTail = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _refresh();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    _followTail = position.extentAfter < 64;
  }

  Future<void> _refresh() async {
    try {
      final file = File(widget.logPath);
      if (!await file.exists()) {
        if (mounted) {
          setState(() => _content = 'Waiting for log file:\n${widget.logPath}');
        }
        return;
      }
      final text = await file.readAsString();
      if (!mounted) {
        return;
      }
      setState(() => _content = text.isEmpty ? '(log file is empty)' : text);
      if (_followTail) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _content = 'Failed to read logs:\n$error');
    }
  }

  Future<void> _clearLogs() async {
    try {
      await File(widget.logPath).writeAsString('', mode: FileMode.write, flush: true);
      await _refresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLogs,
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => windowManager.close(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                widget.logPath,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
