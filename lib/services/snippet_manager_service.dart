import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/snippet_model.dart';
import '../widgets/fuzzy_searchable_dropdown.dart';

class SnippetManagerService extends ChangeNotifier {
  static SnippetManagerService? _instance;
  static SnippetManagerService get instance =>
      _instance ??= SnippetManagerService._();

  @visibleForTesting
  factory SnippetManagerService.forTesting() => SnippetManagerService._();

  SnippetManagerService._();

  final List<SnippetItem> _snippets = [];
  String? _filePath;
  bool _isLoaded = false;

  List<SnippetItem> get snippets => List.unmodifiable(_snippets);
  bool get isLoaded => _isLoaded;

  String _getDefaultFilePath() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return '$home/.nexus_fx/snippets.json';
  }

  Future<void> loadSnippets({String? customFilePath}) async {
    _filePath = customFilePath ?? _getDefaultFilePath();
    final file = File(_filePath!);

    if (!await file.exists()) {
      _snippets.clear();
      _seedDefaultSnippets();
      await saveSnippets();
      _isLoaded = true;
      notifyListeners();
      return;
    }

    try {
      final jsonStr = await file.readAsString();
      if (jsonStr.trim().isEmpty) {
        _snippets.clear();
        _seedDefaultSnippets();
        await saveSnippets();
      } else {
        final decoded = jsonDecode(jsonStr);
        _snippets.clear();
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _snippets.add(SnippetItem.fromJson(item));
            } else if (item is Map) {
              _snippets.add(SnippetItem.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SnippetManagerService] Failed to load snippets: $e');
      if (_snippets.isEmpty) {
        _seedDefaultSnippets();
      }
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> saveSnippets() async {
    _filePath ??= _getDefaultFilePath();
    try {
      final file = File(_filePath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final jsonList = _snippets.map((s) => s.toJson()).toList();
      final tempFile = File('${_filePath!}.tmp');
      await tempFile.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonList));
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(_filePath!);
    } catch (e) {
      debugPrint('[SnippetManagerService] Failed to save snippets: $e');
    }
  }

  Future<SnippetItem> createSnippet({
    required String name,
    required List<String> commands,
    String description = '',
  }) async {
    final item = SnippetItem(
      id: 'snip_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Untitled Snippet' : name.trim(),
      description: description.trim(),
      commands: commands.map((c) => c.trimRight()).where((c) => c.isNotEmpty).toList(),
      modifiedAt: DateTime.now(),
    );

    _snippets.insert(0, item);
    await saveSnippets();
    notifyListeners();
    return item;
  }

  Future<void> updateSnippet(SnippetItem updated) async {
    final index = _snippets.indexWhere((s) => s.id == updated.id);
    if (index != -1) {
      _snippets[index] = updated.copyWith(
        modifiedAt: DateTime.now(),
      );
      await saveSnippets();
      notifyListeners();
    }
  }

  Future<void> deleteSnippet(String id) async {
    final initialCount = _snippets.length;
    _snippets.removeWhere((s) => s.id == id);
    if (_snippets.length != initialCount) {
      await saveSnippets();
      notifyListeners();
    }
  }

  List<SnippetItem> searchSnippets(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return List.unmodifiable(_snippets);
    }

    final scored = <MapEntry<SnippetItem, int>>[];
    for (final snippet in _snippets) {
      int bestScore = 0;

      final nameMatch = FuzzySearchHelper.match(q, snippet.name);
      if (nameMatch != null) {
        bestScore = nameMatch.score + 200; // Name match gets higher priority
      }

      final descMatch = FuzzySearchHelper.match(q, snippet.description);
      if (descMatch != null && descMatch.score > bestScore) {
        bestScore = descMatch.score + 50;
      }

      for (final cmd in snippet.commands) {
        final cmdMatch = FuzzySearchHelper.match(q, cmd);
        if (cmdMatch != null && cmdMatch.score > bestScore) {
          bestScore = cmdMatch.score;
        }
      }

      if (bestScore > 0) {
        scored.add(MapEntry(snippet, bestScore));
      }
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  void _seedDefaultSnippets() {
    _snippets.addAll([
      SnippetItem(
        id: 'snip_nginx_check',
        name: 'Nginx Status & Logs',
        description: 'Check nginx service status and inspect recent log entries',
        commands: [
          'systemctl status nginx --no-pager -n 50',
          'tail -n 30 /var/log/nginx/error.log',
        ],
      ),
      SnippetItem(
        id: 'snip_nginx_restart',
        name: 'Nginx Graceful Reload',
        description: 'Test configuration and gracefully reload nginx service',
        commands: [
          'nginx -t',
          'systemctl reload nginx',
        ],
      ),
      SnippetItem(
        id: 'snip_sys_health',
        name: 'System Health Overview',
        description: 'Check uptime, load averages, memory and disk usage',
        commands: [
          'uptime',
          'free -h',
          'df -h',
        ],
      ),
      SnippetItem(
        id: 'snip_docker_ps',
        name: 'Docker Containers Status',
        description: 'List running containers with stats and disk utilization',
        commands: [
          'docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"',
          'docker system df',
        ],
      ),
      SnippetItem(
        id: 'snip_syslog_tail',
        name: 'Syslog Recent Stream',
        description: 'View the last 50 lines of system logs without pager',
        commands: [
          'journalctl -xe --no-pager -n 50',
        ],
      ),
    ]);
  }
}
