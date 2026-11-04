import 'package:flutter/foundation.dart';
import '../services/ssh_service.dart';

enum BroadcastTarget {
  all,
  left,
  right,
  custom,
}

/// Controller coordinating keyboard broadcast and execution across multiple terminal tabs.
class BroadcastCoordinator extends ChangeNotifier {
  BroadcastTarget _target = BroadcastTarget.all;
  final Set<String> _selectedConnectionIds = {};
  bool _isParallelMode = true;
  bool _isSending = false;

  final List<String> _commandHistory = [];
  int _historyIndex = -1;
  String _commandDraft = '';

  BroadcastTarget get target => _target;
  Set<String> get selectedConnectionIds => _selectedConnectionIds;
  bool get isParallelMode => _isParallelMode;
  bool get isSending => _isSending;
  List<String> get commandHistory => _commandHistory;
  int get historyIndex => _historyIndex;
  String get commandDraft => _commandDraft;

  void setParallelMode(bool parallel) {
    if (_isParallelMode != parallel) {
      _isParallelMode = parallel;
      notifyListeners();
    }
  }

  void setTarget(
    BroadcastTarget target, {
    required List<SshConnection> leftTabs,
    required List<SshConnection> rightTabs,
  }) {
    _target = target;
    _syncTargetSelection(leftTabs: leftTabs, rightTabs: rightTabs);
    notifyListeners();
  }

  void _syncTargetSelection({
    required List<SshConnection> leftTabs,
    required List<SshConnection> rightTabs,
  }) {
    if (_target == BroadcastTarget.all) {
      _selectedConnectionIds.clear();
      _selectedConnectionIds.addAll(
        [...leftTabs, ...rightTabs].where((c) => c.isConnected).map((c) => c.id),
      );
    } else if (_target == BroadcastTarget.left) {
      _selectedConnectionIds.clear();
      _selectedConnectionIds.addAll(
        leftTabs.where((c) => c.isConnected).map((c) => c.id),
      );
    } else if (_target == BroadcastTarget.right) {
      _selectedConnectionIds.clear();
      _selectedConnectionIds.addAll(
        rightTabs.where((c) => c.isConnected).map((c) => c.id),
      );
    }
  }

  void clearSelection() {
    _selectedConnectionIds.clear();
    notifyListeners();
  }

  void selectPresetTarget(
    BroadcastTarget target, {
    required List<SshConnection> leftTabs,
    required List<SshConnection> rightTabs,
  }) {
    _target = target;
    _selectedConnectionIds.clear();
    switch (target) {
      case BroadcastTarget.all:
        _selectedConnectionIds.addAll(
          [...leftTabs, ...rightTabs].map((c) => c.id),
        );
        break;
      case BroadcastTarget.left:
        _selectedConnectionIds.addAll(
          leftTabs.map((c) => c.id),
        );
        break;
      case BroadcastTarget.right:
        _selectedConnectionIds.addAll(
          rightTabs.map((c) => c.id),
        );
        break;
      case BroadcastTarget.custom:
        break;
    }
    notifyListeners();
  }

  void updateBroadcastTargetFromSelection({
    required List<SshConnection> leftTabs,
    required List<SshConnection> rightTabs,
  }) {
    final allIds = [...leftTabs, ...rightTabs].map((c) => c.id).toSet();
    final leftIds = leftTabs.map((c) => c.id).toSet();
    final rightIds = rightTabs.map((c) => c.id).toSet();

    if (_selectedConnectionIds.isNotEmpty &&
        _selectedConnectionIds.length == allIds.length &&
        _selectedConnectionIds.containsAll(allIds)) {
      _target = BroadcastTarget.all;
    } else if (_selectedConnectionIds.isNotEmpty &&
        _selectedConnectionIds.length == leftIds.length &&
        _selectedConnectionIds.containsAll(leftIds)) {
      _target = BroadcastTarget.left;
    } else if (_selectedConnectionIds.isNotEmpty &&
        _selectedConnectionIds.length == rightIds.length &&
        _selectedConnectionIds.containsAll(rightIds)) {
      _target = BroadcastTarget.right;
    } else {
      _target = BroadcastTarget.custom;
    }
    notifyListeners();
  }

  void toggleSelection(String connectionId) {
    if (_selectedConnectionIds.contains(connectionId)) {
      _selectedConnectionIds.remove(connectionId);
    } else {
      _selectedConnectionIds.add(connectionId);
    }
    notifyListeners();
  }

  void handleNewConnection(
    SshConnection conn, {
    required bool isRightPane,
  }) {
    if (_target == BroadcastTarget.all ||
        (_target == BroadcastTarget.left && !isRightPane) ||
        (_target == BroadcastTarget.right && isRightPane)) {
      _selectedConnectionIds.add(conn.id);
      notifyListeners();
    }
  }

  void removeConnection(String connectionId) {
    if (_selectedConnectionIds.remove(connectionId)) {
      notifyListeners();
    }
  }

  void recordCommand(String rawCommand) {
    final trimmed = rawCommand.trim();
    if (trimmed.isEmpty) return;

    if (_commandHistory.isEmpty || _commandHistory.last != rawCommand) {
      _commandHistory.add(rawCommand);
    }
    _historyIndex = -1;
    _commandDraft = '';
    notifyListeners();
  }

  String? navigateHistoryUp(String currentInput) {
    if (_commandHistory.isEmpty) return null;

    if (_historyIndex == -1) {
      _commandDraft = currentInput;
      _historyIndex = _commandHistory.length - 1;
    } else if (_historyIndex > 0) {
      _historyIndex--;
    }

    return _commandHistory[_historyIndex];
  }

  String? navigateHistoryDown() {
    if (_historyIndex == -1) return null;

    if (_historyIndex < _commandHistory.length - 1) {
      _historyIndex++;
      return _commandHistory[_historyIndex];
    } else {
      _historyIndex = -1;
      return _commandDraft;
    }
  }

  void resetHistoryNavigation() {
    _historyIndex = -1;
    _commandDraft = '';
  }

  List<SshConnection> resolveTargetConnections({
    required List<SshConnection> leftTabs,
    required List<SshConnection> rightTabs,
    required bool isSplitView,
  }) {
    if (_target == BroadcastTarget.custom) {
      return [...leftTabs, ...rightTabs]
          .where((c) => c.isConnected && _selectedConnectionIds.contains(c.id))
          .toList();
    }

    if (!isSplitView) {
      return leftTabs.where((c) => c.isConnected).toList();
    }

    switch (_target) {
      case BroadcastTarget.left:
        return leftTabs.where((c) => c.isConnected).toList();
      case BroadcastTarget.right:
        return rightTabs.where((c) => c.isConnected).toList();
      case BroadcastTarget.all:
        return [...leftTabs, ...rightTabs].where((c) => c.isConnected).toList();
      case BroadcastTarget.custom:
        return [];
    }
  }

  Future<void> executeBroadcast({
    required List<SshConnection> targetConnections,
    required String rawText,
    Future<void> Function(SshConnection conn, String cmd)? customSender,
  }) async {
    final isBlank = rawText.trim().isEmpty;
    final lines = isBlank
        ? ['']
        : rawText
            .split(RegExp(r'\r?\n'))
            .where((line) => line.trim().isNotEmpty)
            .toList();

    if (lines.isEmpty) return;

    recordCommand(rawText);

    _isSending = true;
    notifyListeners();

    try {
      for (final line in lines) {
        if (_isParallelMode) {
          await Future.wait(
            targetConnections.map((conn) {
              if (customSender != null) {
                return customSender(conn, line);
              }
              return conn.sendCommandAndWaitForPrompt(command: line);
            }),
          );
        } else {
          for (final conn in targetConnections) {
            if (customSender != null) {
              await customSender(conn, line);
            } else {
              await conn.sendCommandAndWaitForPrompt(command: line);
            }
          }
        }
      }
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }
}
