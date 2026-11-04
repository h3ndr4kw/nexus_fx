import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../theme/app_theme.dart';
import '../theme/terminal_theme_helper.dart';
import '../services/settings_service.dart';
import '../services/ssh_service.dart';
import '../services/ssh_log_service.dart';

class SshTabView extends StatefulWidget {
  final SshConnection connection;
  final VoidCallback onClose;
  final bool isActive;
  final VoidCallback? onFocus;

  const SshTabView({
    super.key,
    required this.connection,
    required this.onClose,
    this.isActive = true,
    this.onFocus,
  });

  @override
  State<SshTabView> createState() => SshTabViewState();
}

class SshTabViewState extends State<SshTabView> {
  Terminal get _terminal => widget.connection.terminal;
  TerminalController get _controller => widget.connection.terminalController;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _isFocused = false;
  bool _isConnecting = true;
  bool _wasEverConnected = false;
  bool _isSessionStopped = false;
  String? _error;
  StreamSubscription<bool>? _connectionSubscription;
  double _fontSize = 14.0;
  bool _isContextMenuOpen = false;

  void requestFocus() {
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  void _zoomIn() {
    setState(() {
      _fontSize = (_fontSize + 1.0).clamp(8.0, 36.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _fontSize = (_fontSize - 1.0).clamp(8.0, 36.0);
    });
  }

  void _zoomReset() {
    setState(() {
      _fontSize = SettingsService.instance.nexusTerminalFontSize;
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final isCtrl = HardwareKeyboard.instance.isControlPressed;
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if (isCtrl && isShift) {
        if (event.scrollDelta.dy < 0) {
          _zoomIn();
        } else if (event.scrollDelta.dy > 0) {
          _zoomOut();
        }
      }
    }
  }

  void _showSessionStoppedPrompt() {
    _terminal.write(
      '\r\n\x1b[90m────────────────────────────────────────────────────────────────────────────────\x1b[0m\r\n'
      '\x1b[31mSession stopped\x1b[0m\r\n'
      '    - Press \x1b[35m<Return>\x1b[0m to exit tab\r\n'
      '    - Press \x1b[35mR\x1b[0m to restart session\r\n\r\n',
    );
  }

  String _getAllTerminalText() {
    final buffer = StringBuffer();
    for (int i = 0; i < _terminal.buffer.lines.length; i++) {
      final line = _terminal.buffer.lines[i];
      buffer.writeln(line.getText());
    }
    return buffer.toString().trimRight();
  }

  Future<void> _saveTerminalOutputToFile() async {
    try {
      final text = _getAllTerminalText();
      final now = DateTime.now();
      final logSvc = widget.connection.logService ?? SshLogService.instance;
      final dateStr = logSvc.formatDate(now);
      final dateTimeStr = logSvc.formatDateTime(now);

      final hostName = widget.connection.currentLabel.isNotEmpty
          ? widget.connection.currentLabel
          : widget.connection.currentHost;
      final safeHost = hostName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      final baseDir = logSvc.baseDir ?? Directory.current.path;
      final dir = Directory(
          '$baseDir${Platform.pathSeparator}logs${Platform.pathSeparator}nexus${Platform.pathSeparator}$dateStr');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final file = File(
          '${dir.path}${Platform.pathSeparator}terminal_${safeHost}_$dateTimeStr.log');
      file.writeAsStringSync(text, flush: true);

      _terminal.write(
          '\r\n\x1b[32m✔ Terminal output saved to: ${file.path}\x1b[0m\r\n');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Terminal output saved to ${file.path}'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _terminal
          .write('\r\n\x1b[31m✖ Failed to save terminal output: $e\x1b[0m\r\n');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save terminal output: $e'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _restartSession() {
    setState(() {
      _isSessionStopped = false;
      _isConnecting = true;
      _error = null;
    });
    _terminal.write(
        '\r\n\x1b[33m[SYS] Restarting session to ${widget.connection.currentHost}...\x1b[0m\r\n');
    _connect();
  }

  void _onFocusChange() {
    if (mounted && _isFocused != _focusNode.hasFocus) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (_focusNode.hasFocus) {
        widget.onFocus?.call();
      }
    }
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {
        _fontSize = SettingsService.instance.nexusTerminalFontSize;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fontSize = SettingsService.instance.nexusTerminalFontSize;
    SettingsService.instance.addListener(_onSettingsChanged);
    _isFocused = _focusNode.hasFocus;
    _focusNode.addListener(_onFocusChange);
    _wasEverConnected = widget.connection.isConnected;

    _connectionSubscription =
        widget.connection.connectionState.listen((connected) {
      if (connected) {
        _wasEverConnected = true;
        _isSessionStopped = false;
        _isConnecting = false;
        if (mounted && widget.isActive) {
          _focusNode.requestFocus();
        }
      }
      if (!connected && mounted && !_isConnecting) {
        if (_wasEverConnected && !_isSessionStopped) {
          setState(() {
            _isSessionStopped = true;
          });
          _showSessionStoppedPrompt();
          _focusNode.requestFocus();
        } else if (!_wasEverConnected) {
          setState(() {
            _error = 'Disconnected from ${widget.connection.currentHost}';
          });
        }
      }
    });

    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) {
          _focusNode.requestFocus();
        }
      });
    }

    _connect();
  }

  @override
  void didUpdateWidget(SshTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive &&
        (!oldWidget.isActive || widget.connection != oldWidget.connection)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    _focusNode.removeListener(_onFocusChange);
    _scrollController.dispose();
    _connectionSubscription?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  String? get _selectedText {
    final selection = _controller.selection;
    if (selection == null) return null;
    return _terminal.buffer.getText(selection);
  }

  Future<void> _copySelection() async {
    final text = _selectedText;
    if (text != null && text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      _terminal.paste(text);
      _controller.clearSelection();
    }
  }

  void _selectAll() {
    if (_terminal.buffer.lines.length == 0) return;
    final lastLineIndex = _terminal.buffer.lines.length - 1;
    final lastLineWidth = _terminal.buffer.lines[lastLineIndex].length;
    _controller.setSelection(
      _terminal.buffer.createAnchor(0, 0),
      _terminal.buffer.createAnchor(lastLineWidth, lastLineIndex),
      mode: SelectionMode.line,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
    final isShift = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
    final isAlt = HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altRight);

    if (_isSessionStopped) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        widget.onClose();
        return KeyEventResult.handled;
      }

      if (!isCtrl && !isAlt && !isShift) {
        if (event.logicalKey == LogicalKeyboardKey.keyR) {
          _restartSession();
          return KeyEventResult.handled;
        }
      }
    }

    // Smart Ctrl+C: Copy if selection exists, otherwise send SIGINT (\x03)
    if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (_controller.selection != null) {
        _copySelection();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Explicit Ctrl+Shift+C: Copy selection
    if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (_controller.selection != null) {
        _copySelection();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    // Ctrl+V, Ctrl+Shift+V, Shift+Insert: Paste from clipboard
    final isPasteKey = (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) ||
        (isShift && event.logicalKey == LogicalKeyboardKey.insert);

    if (isPasteKey) {
      _pasteFromClipboard();
      return KeyEventResult.handled;
    }

    // Ctrl+A: Select All
    if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyA) {
      _selectAll();
      return KeyEventResult.handled;
    }

    // Toggle Command Pane: Ctrl + Shift + Space (prevent TerminalView from writing \x00)
    final isSpace = event.logicalKey == LogicalKeyboardKey.space ||
        event.physicalKey == PhysicalKeyboardKey.space;
    if (isCtrl && isShift && isSpace) {
      return KeyEventResult.handled;
    }

    // Tab Navigation & Shortcuts: prevent TerminalView from writing control characters (e.g. \t, \x14, \x17, escape codes)
    if (isCtrl && !isAlt &&
        (event.logicalKey == LogicalKeyboardKey.tab ||
            event.logicalKey == LogicalKeyboardKey.keyT ||
            event.logicalKey == LogicalKeyboardKey.keyW ||
            event.logicalKey == LogicalKeyboardKey.keyQ ||
            event.logicalKey == LogicalKeyboardKey.pageDown ||
            event.logicalKey == LogicalKeyboardKey.pageUp)) {
      return KeyEventResult.handled;
    }
    if (isAlt && !isCtrl && _isDigitKey(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (isAlt &&
        !isCtrl &&
        !isShift &&
        (event.logicalKey == LogicalKeyboardKey.keyL ||
            event.physicalKey == PhysicalKeyboardKey.keyL ||
            event.logicalKey == LogicalKeyboardKey.keyH ||
            event.physicalKey == PhysicalKeyboardKey.keyH)) {
      return KeyEventResult.handled;
    }

    // Zoom In: Ctrl + Shift + (+ or = or numpadAdd) or Ctrl + (numpadAdd)
    if ((isCtrl &&
            isShift &&
            (event.logicalKey == LogicalKeyboardKey.equal ||
                event.logicalKey == LogicalKeyboardKey.add ||
                event.logicalKey == LogicalKeyboardKey.numpadAdd)) ||
        (isCtrl &&
            (event.logicalKey == LogicalKeyboardKey.add ||
                event.logicalKey == LogicalKeyboardKey.numpadAdd))) {
      _zoomIn();
      return KeyEventResult.handled;
    }

    // Zoom Out: Ctrl + Shift + (- or numpadSubtract) or Ctrl + (- or numpadSubtract)
    if ((isCtrl &&
            isShift &&
            (event.logicalKey == LogicalKeyboardKey.minus ||
                event.logicalKey == LogicalKeyboardKey.numpadSubtract)) ||
        (isCtrl &&
            (event.logicalKey == LogicalKeyboardKey.minus ||
                event.logicalKey == LogicalKeyboardKey.numpadSubtract))) {
      _zoomOut();
      return KeyEventResult.handled;
    }

    // Zoom Reset: Ctrl + Shift + (0 or numpad0) or Ctrl + (0 or numpad0)
    if (isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.digit0 ||
            event.logicalKey == LogicalKeyboardKey.numpad0)) {
      _zoomReset();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _isDigitKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1 ||
        key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2 ||
        key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3 ||
        key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4 ||
        key == LogicalKeyboardKey.digit5 ||
        key == LogicalKeyboardKey.numpad5 ||
        key == LogicalKeyboardKey.digit6 ||
        key == LogicalKeyboardKey.numpad6 ||
        key == LogicalKeyboardKey.digit7 ||
        key == LogicalKeyboardKey.numpad7 ||
        key == LogicalKeyboardKey.digit8 ||
        key == LogicalKeyboardKey.numpad8 ||
        key == LogicalKeyboardKey.digit9 ||
        key == LogicalKeyboardKey.numpad9;
  }

  Future<void> _showContextMenu(Offset globalPosition) async {
    if (_isContextMenuOpen) return;
    _isContextMenuOpen = true;

    try {
      _focusNode.requestFocus();
      final hasSelection = _controller.selection != null;
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final hasClipboard = clipData?.text != null && clipData!.text!.isNotEmpty;

      if (!mounted) return;

      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      final overlayRect = overlay != null
          ? Offset.zero & overlay.size
          : Offset.zero & MediaQuery.of(context).size;

      final position = RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        overlayRect,
      );

      final selected = await showMenu<String>(
        context: context,
        position: position,
        color: AppTheme.surfaceColor,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: AppTheme.inputBorderColor),
        ),
        items: [
          PopupMenuItem<String>(
            value: 'copy',
            height: 36,
            child: Row(
              children: [
                Icon(
                  Icons.copy,
                  size: 14,
                  color: hasSelection ? AppTheme.textColor : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Copy',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasSelection ? AppTheme.textColor : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Ctrl+C',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'paste',
            height: 36,
            child: Row(
              children: [
                Icon(
                  Icons.paste,
                  size: 14,
                  color: hasClipboard ? AppTheme.textColor : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Paste',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasClipboard ? AppTheme.textColor : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Ctrl+V',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(height: 1),
          const PopupMenuItem<String>(
            value: 'select_all',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.select_all, size: 14, color: AppTheme.textColor),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Select All',
                    style: TextStyle(fontSize: 12, color: AppTheme.textColor),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Ctrl+A',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'clear',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.clear_all, size: 14, color: AppTheme.textColor),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Clear Buffer',
                    style: TextStyle(fontSize: 12, color: AppTheme.textColor),
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'save_output',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.save_alt, size: 14, color: AppTheme.textColor),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Save Output to File',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textColor),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'S',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (widget.connection.logFile != null)
            const PopupMenuItem<String>(
              value: 'open_log',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 14, color: AppTheme.accentPrimary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Copy Session Log Path',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppTheme.textColor),
                    ),
                  ),
                ],
              ),
            ),
          const PopupMenuDivider(height: 1),
          const PopupMenuItem<String>(
            value: 'zoom_in',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.zoom_in, size: 14, color: AppTheme.textColor),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Zoom In',
                    style: TextStyle(fontSize: 12, color: AppTheme.textColor),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Ctrl++',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'zoom_out',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.zoom_out, size: 14, color: AppTheme.textColor),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Zoom Out',
                    style: TextStyle(fontSize: 12, color: AppTheme.textColor),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Ctrl+-',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'zoom_reset',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.restart_alt, size: 14, color: AppTheme.textColor),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reset Zoom',
                    style: TextStyle(fontSize: 12, color: AppTheme.textColor),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Ctrl+0',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      );

      if (!mounted || selected == null) return;

      switch (selected) {
        case 'copy':
          if (hasSelection) {
            await _copySelection();
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No text selected to copy'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
          break;
        case 'paste':
          if (hasClipboard) {
            await _pasteFromClipboard();
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Clipboard is empty'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
          break;
        case 'select_all':
          _selectAll();
          break;
        case 'clear':
          _terminal.buffer.clear();
          _controller.clearSelection();
          break;
        case 'save_output':
          await _saveTerminalOutputToFile();
          break;
        case 'open_log':
          final logFile = widget.connection.logFile;
          if (logFile != null) {
            await Clipboard.setData(ClipboardData(text: logFile.path));
            if (Platform.isWindows && logFile.existsSync()) {
              Process.run('explorer.exe', ['/select,', logFile.path]);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Log path copied & opened: ${logFile.path}'),
                  backgroundColor: AppTheme.successColor,
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
          break;
        case 'zoom_in':
          _zoomIn();
          break;
        case 'zoom_out':
          _zoomOut();
          break;
        case 'zoom_reset':
          _zoomReset();
          break;
      }
    } finally {
      _isContextMenuOpen = false;
    }
  }

  Future<void> _connect() async {
    if (widget.connection.isConnected || widget.connection.isConnecting) {
      if (mounted) {
        setState(() {
          _isConnecting = widget.connection.isConnecting;
        });
      }
      return;
    }
    final username =
        widget.connection.targetUsername ?? 'root';
    final password = widget.connection.targetPassword ?? '';

    final success = await widget.connection.connect(
      targetUsername: username,
      targetPassword: password,
    );

    if (mounted) {
      setState(() {
        _isConnecting = false;
        if (!success) {
          _error = 'Failed to connect to ${widget.connection.currentHost}';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    final terminalTheme = TerminalThemeHelper.resolveTheme(
      mode: settings.nexusTerminalThemeMode,
      palette: AppTheme.activePalette,
    );

    return Container(
      color: terminalTheme.background,
      child: Stack(
        children: [
        Listener(
          onPointerSignal: _handlePointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focusNode.requestFocus();
            },
            onSecondaryTapDown: (details) {
              _showContextMenu(details.globalPosition);
            },
            child: ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: _isFocused,
                thickness: 8.0,
                radius: const Radius.circular(4.0),
                thumbColor: AppTheme.inputBorderColor.withValues(alpha: 0.8),
                interactive: true,
                child: TerminalView(
                  _terminal,
                  controller: _controller,
                  scrollController: _scrollController,
                  focusNode: _focusNode,
                  theme: terminalTheme,
                  autofocus: true,
                  alwaysShowCursor: true,
                  deleteDetection: true,
                  hardwareKeyboardOnly: true,
                  onKeyEvent: _handleKeyEvent,
                  onSecondaryTapDown: (details, offset) {
                    _showContextMenu(details.globalPosition);
                  },
                  textStyle: TerminalStyle(
                    fontSize: _fontSize,
                    height: settings.nexusTerminalLineHeight,
                    fontFamily: settings.nexusTerminalFontFamily.fontFamily,
                  ),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
          ),
        ),
        if (_error != null &&
            !widget.connection.isConnected &&
            !_isConnecting &&
            !_isSessionStopped)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: AppTheme.errorColor.withValues(alpha: 0.9),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isConnecting = true;
                        _error = null;
                      });
                      _connect();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                    ),
                    child: const Text('Retry', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.onClose,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                    ),
                    child: const Text('Close Tab', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  }
}
