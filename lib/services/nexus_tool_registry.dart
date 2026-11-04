import 'package:flutter/foundation.dart';
import '../models/nexus_tool.dart';

/// Registry managing custom [NexusTool] extensions added by host or downstream applications.
class NexusToolRegistry extends ChangeNotifier {
  static final NexusToolRegistry instance = NexusToolRegistry._internal();

  NexusToolRegistry._internal();

  @visibleForTesting
  NexusToolRegistry.forTesting();

  final List<NexusTool> _tools = [];

  /// Unmodifiable list of registered custom tools in registration order.
  List<NexusTool> get tools => List.unmodifiable(_tools);

  /// Registers a custom [tool]. If a tool with the same [NexusTool.id] already exists,
  /// it is replaced in-place.
  void registerTool(NexusTool tool) {
    final existingIdx = _tools.indexWhere((t) => t.id == tool.id);
    if (existingIdx != -1) {
      _tools[existingIdx] = tool;
    } else {
      _tools.add(tool);
    }
    notifyListeners();
  }

  /// Registers multiple custom [tools] at once.
  void registerAll(Iterable<NexusTool> tools) {
    bool changed = false;
    for (final tool in tools) {
      final existingIdx = _tools.indexWhere((t) => t.id == tool.id);
      if (existingIdx != -1) {
        _tools[existingIdx] = tool;
      } else {
        _tools.add(tool);
      }
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Removes a registered tool by its [id].
  void unregisterTool(String id) {
    final beforeLen = _tools.length;
    _tools.removeWhere((t) => t.id == id);
    if (_tools.length != beforeLen) {
      notifyListeners();
    }
  }

  /// Clears all registered custom tools.
  void clear() {
    if (_tools.isNotEmpty) {
      _tools.clear();
      notifyListeners();
    }
  }

  /// Looks up a registered tool by [id], or returns `null` if not found.
  NexusTool? getToolById(String id) {
    for (final tool in _tools) {
      if (tool.id == id) return tool;
    }
    return null;
  }
}
