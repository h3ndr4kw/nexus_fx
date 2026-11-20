import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// A process running inside a Windows pseudo console (ConPTY).
///
/// Programs started this way see a real console: `isatty` is true, so
/// interactive tools (Claude Code, vim, ssh, PSReadLine) behave as they do in
/// Windows Terminal, and Unicode output reaches us as UTF-8 VT sequences
/// instead of being squeezed through the OEM code page.
class WindowsConPty {
  WindowsConPty._(
    this._hPC,
    this._inputWrite,
    this._outputRead,
    this._hProcess,
    this._hThread,
  );

  final int _hPC;
  final int _inputWrite;
  final int _outputRead;
  final int _hProcess;
  final int _hThread;

  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();
  bool _closed = false;
  bool _readerDone = false;

  /// Bytes the console host writes: UTF-8 text with VT escape sequences.
  Stream<Uint8List> get output => _output.stream;

  /// Completes with the process exit code once it has terminated.
  Future<int> get exitCode => _exitCode.future;

  static Future<WindowsConPty> start(
    String executable,
    List<String> arguments, {
    int columns = 80,
    int rows = 24,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final k = _Kernel32.instance;
    final handles = calloc<IntPtr>(4);
    final hPCOut = calloc<IntPtr>();
    final attrSize = calloc<IntPtr>();
    final si = calloc<_StartupInfoEx>();
    final pi = calloc<_ProcessInformation>();
    Pointer<Void> attrList = nullptr;
    Pointer<Utf16> cmdLine = nullptr;
    Pointer<Uint16> envBlock = nullptr;
    Pointer<Utf16> cwd = nullptr;
    var hPC = 0;
    var attrListReady = false;
    // handles: [inputRead, inputWrite, outputRead, outputWrite]
    void closeAll() {
      for (var i = 0; i < 4; i++) {
        if (handles[i] != 0) k.closeHandle(handles[i]);
        handles[i] = 0;
      }
      if (hPC != 0) k.closePseudoConsole(hPC);
      hPC = 0;
    }

    try {
      if (k.createPipe(handles + 0, handles + 1, nullptr, 0) == 0 ||
          k.createPipe(handles + 2, handles + 3, nullptr, 0) == 0) {
        throw OSError('CreatePipe failed', k.getLastError());
      }

      final size = calloc<_Coord>();
      size.ref
        ..x = columns.clamp(1, 32767)
        ..y = rows.clamp(1, 32767);
      final hr = k.createPseudoConsole(size.ref, handles[0], handles[3], 0, hPCOut);
      calloc.free(size);
      if (hr != 0) {
        throw OSError('CreatePseudoConsole failed (HRESULT 0x${(hr & 0xFFFFFFFF).toRadixString(16)})', hr);
      }
      hPC = hPCOut.value;

      // The console host holds its own copies of these ends.
      k.closeHandle(handles[0]);
      handles[0] = 0;
      k.closeHandle(handles[3]);
      handles[3] = 0;

      k.initializeProcThreadAttributeList(nullptr, 1, 0, attrSize);
      attrList = calloc<Uint8>(attrSize.value).cast();
      if (k.initializeProcThreadAttributeList(attrList, 1, 0, attrSize) == 0) {
        throw OSError('InitializeProcThreadAttributeList failed', k.getLastError());
      }
      attrListReady = true;
      if (k.updateProcThreadAttribute(attrList, 0, _procThreadAttributePseudoConsole,
              Pointer<Void>.fromAddress(hPC), sizeOf<IntPtr>(), nullptr, nullptr) ==
          0) {
        throw OSError('UpdateProcThreadAttribute failed', k.getLastError());
      }

      si.ref
        ..cb = sizeOf<_StartupInfoEx>()
        // Null std handles: without this the child inherits ours when this
        // process has redirected stdio (flutter run, tests) and writes there
        // instead of to the pseudo console.
        ..dwFlags = _startfUseStdHandles
        ..lpAttributeList = attrList;

      cmdLine = buildCommandLine(executable, arguments).toNativeUtf16();
      envBlock = _buildEnvironmentBlock(environment ?? Platform.environment);
      if (workingDirectory != null) cwd = workingDirectory.toNativeUtf16();

      final ok = k.createProcess(
        nullptr,
        cmdLine,
        nullptr,
        nullptr,
        0,
        _extendedStartupInfoPresent | _createUnicodeEnvironment,
        envBlock.cast(),
        cwd,
        si.cast(),
        pi,
      );
      if (ok == 0) {
        throw OSError('CreateProcess failed for $executable', k.getLastError());
      }

      final pty = WindowsConPty._(
        hPC,
        handles[1],
        handles[2],
        pi.ref.hProcess,
        pi.ref.hThread,
      );
      handles[1] = 0;
      handles[2] = 0;
      hPC = 0;
      await pty._startWorkers();
      return pty;
    } catch (_) {
      closeAll();
      rethrow;
    } finally {
      if (attrListReady) k.deleteProcThreadAttributeList(attrList);
      if (attrList != nullptr) calloc.free(attrList);
      if (cmdLine != nullptr) calloc.free(cmdLine);
      if (envBlock != nullptr) calloc.free(envBlock);
      if (cwd != nullptr) calloc.free(cwd);
      calloc.free(handles);
      calloc.free(hPCOut);
      calloc.free(attrSize);
      calloc.free(si);
      calloc.free(pi);
    }
  }

  Future<void> _startWorkers() async {
    final readPort = ReceivePort();
    final exitPort = ReceivePort();

    readPort.listen((message) {
      if (message is TransferableTypedData) {
        if (!_output.isClosed) {
          _output.add(message.materialize().asUint8List());
        }
      } else {
        _readerDone = true;
        readPort.close();
        if (!_output.isClosed) _output.close();
        _releaseIfDone();
      }
    });
    exitPort.listen((message) {
      exitPort.close();
      final code = message is int ? message : -1;
      // Closing the pseudo console ends its output pipe, which lets the
      // reader drain what is left and finish.
      _closePseudoConsole();
      if (!_exitCode.isCompleted) _exitCode.complete(code);
      _releaseIfDone();
    });

    await Isolate.spawn(_readLoop, [readPort.sendPort, _outputRead],
        debugName: 'conpty-read');
    await Isolate.spawn(_waitLoop, [exitPort.sendPort, _hProcess],
        debugName: 'conpty-wait');
  }

  bool _pcClosed = false;
  void _closePseudoConsole() {
    if (_pcClosed) return;
    _pcClosed = true;
    _Kernel32.instance.closePseudoConsole(_hPC);
  }

  void _releaseIfDone() {
    if (_closed || !_readerDone || !_exitCode.isCompleted) return;
    _closed = true;
    final k = _Kernel32.instance;
    k.closeHandle(_inputWrite);
    k.closeHandle(_outputRead);
    k.closeHandle(_hThread);
    k.closeHandle(_hProcess);
  }

  /// Sends [data] to the console as keyboard input.
  void write(List<int> data) {
    if (data.isEmpty || _pcClosed) return;
    final k = _Kernel32.instance;
    final buf = calloc<Uint8>(data.length);
    final written = calloc<Uint32>();
    try {
      buf.asTypedList(data.length).setAll(0, data);
      var offset = 0;
      while (offset < data.length) {
        final ok = k.writeFile(_inputWrite, (buf + offset).cast(),
            data.length - offset, written, nullptr);
        if (ok == 0 || written.value == 0) break;
        offset += written.value;
      }
    } finally {
      calloc.free(buf);
      calloc.free(written);
    }
  }

  void resize(int columns, int rows) {
    if (_pcClosed || columns <= 0 || rows <= 0) return;
    final size = calloc<_Coord>();
    try {
      size.ref
        ..x = columns.clamp(1, 32767)
        ..y = rows.clamp(1, 32767);
      _Kernel32.instance.resizePseudoConsole(_hPC, size.ref);
    } finally {
      calloc.free(size);
    }
  }

  /// Terminates the process; [exitCode] completes once it is gone.
  void kill() {
    if (_exitCode.isCompleted) return;
    _Kernel32.instance.terminateProcess(_hProcess, 1);
  }

  /// Joins [executable] and [arguments] into a command line that
  /// `CommandLineToArgvW` (and the MSVC runtime) splits back unchanged.
  @visibleForTesting
  static String buildCommandLine(String executable, List<String> arguments) =>
      [executable, ...arguments].map(_quoteArgument).join(' ');

  static String _quoteArgument(String arg) {
    if (arg.isNotEmpty && !arg.contains(RegExp(r'[ \t\n\v"]'))) return arg;
    final sb = StringBuffer('"');
    var backslashes = 0;
    for (final unit in arg.codeUnits) {
      if (unit == 0x5C) {
        backslashes++;
        continue;
      }
      if (unit == 0x22) {
        sb.write(r'\' * (backslashes * 2 + 1));
      } else {
        sb.write(r'\' * backslashes);
      }
      sb.writeCharCode(unit);
      backslashes = 0;
    }
    sb.write(r'\' * (backslashes * 2));
    sb.write('"');
    return sb.toString();
  }

  /// UTF-16 `NAME=value\0...\0\0` block, sorted by name as CreateProcess
  /// expects.
  static Pointer<Uint16> _buildEnvironmentBlock(Map<String, String> env) {
    final entries = env.entries
        .where((e) => e.key.isNotEmpty && !e.key.startsWith('='))
        .toList()
      ..sort((a, b) => a.key.toUpperCase().compareTo(b.key.toUpperCase()));
    final units = <int>[];
    for (final e in entries) {
      units
        ..addAll('${e.key}=${e.value}'.codeUnits)
        ..add(0);
    }
    if (entries.isEmpty) units.add(0);
    units.add(0);
    final block = calloc<Uint16>(units.length);
    block.asTypedList(units.length).setAll(0, units);
    return block;
  }
}

void _readLoop(List<Object> args) {
  final port = args[0] as SendPort;
  final handle = args[1] as int;
  final k = _Kernel32.instance;
  const bufSize = 64 * 1024;
  final buf = calloc<Uint8>(bufSize);
  final read = calloc<Uint32>();
  try {
    while (true) {
      final ok = k.readFile(handle, buf.cast(), bufSize, read, nullptr);
      if (ok == 0 || read.value == 0) break;
      port.send(TransferableTypedData.fromList(
          [Uint8List.fromList(buf.asTypedList(read.value))]));
    }
  } finally {
    calloc.free(buf);
    calloc.free(read);
    port.send(null);
  }
}

void _waitLoop(List<Object> args) {
  final port = args[0] as SendPort;
  final hProcess = args[1] as int;
  final k = _Kernel32.instance;
  k.waitForSingleObject(hProcess, _infinite);
  final code = calloc<Uint32>();
  try {
    k.getExitCodeProcess(hProcess, code);
    port.send(code.value.toSigned(32));
  } finally {
    calloc.free(code);
  }
}

const _procThreadAttributePseudoConsole = 0x00020016;
const _extendedStartupInfoPresent = 0x00080000;
const _createUnicodeEnvironment = 0x00000400;
const _startfUseStdHandles = 0x00000100;
const _infinite = 0xFFFFFFFF;

final class _Coord extends Struct {
  @Int16()
  external int x;
  @Int16()
  external int y;
}

final class _StartupInfoEx extends Struct {
  @Uint32()
  external int cb;
  external Pointer<Utf16> lpReserved;
  external Pointer<Utf16> lpDesktop;
  external Pointer<Utf16> lpTitle;
  @Uint32()
  external int dwX;
  @Uint32()
  external int dwY;
  @Uint32()
  external int dwXSize;
  @Uint32()
  external int dwYSize;
  @Uint32()
  external int dwXCountChars;
  @Uint32()
  external int dwYCountChars;
  @Uint32()
  external int dwFillAttribute;
  @Uint32()
  external int dwFlags;
  @Uint16()
  external int wShowWindow;
  @Uint16()
  external int cbReserved2;
  external Pointer<Uint8> lpReserved2;
  @IntPtr()
  external int hStdInput;
  @IntPtr()
  external int hStdOutput;
  @IntPtr()
  external int hStdError;
  external Pointer<Void> lpAttributeList;
}

final class _ProcessInformation extends Struct {
  @IntPtr()
  external int hProcess;
  @IntPtr()
  external int hThread;
  @Uint32()
  external int dwProcessId;
  @Uint32()
  external int dwThreadId;
}

class _Kernel32 {
  _Kernel32._(DynamicLibrary lib)
      : createPipe = lib.lookupFunction<
            Int32 Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, Uint32),
            int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, int)>('CreatePipe'),
        closeHandle =
            lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle'),
        createPseudoConsole = lib.lookupFunction<
            Int32 Function(_Coord, IntPtr, IntPtr, Uint32, Pointer<IntPtr>),
            int Function(_Coord, int, int, int, Pointer<IntPtr>)>('CreatePseudoConsole'),
        resizePseudoConsole = lib.lookupFunction<Int32 Function(IntPtr, _Coord),
            int Function(int, _Coord)>('ResizePseudoConsole'),
        closePseudoConsole = lib.lookupFunction<Void Function(IntPtr), void Function(int)>(
            'ClosePseudoConsole'),
        initializeProcThreadAttributeList = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Uint32, Uint32, Pointer<IntPtr>),
            int Function(Pointer<Void>, int, int, Pointer<IntPtr>)>(
          'InitializeProcThreadAttributeList',
        ),
        updateProcThreadAttribute = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Uint32, UintPtr, Pointer<Void>, IntPtr,
                Pointer<Void>, Pointer<IntPtr>),
            int Function(Pointer<Void>, int, int, Pointer<Void>, int, Pointer<Void>,
                Pointer<IntPtr>)>('UpdateProcThreadAttribute'),
        deleteProcThreadAttributeList =
            lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
          'DeleteProcThreadAttributeList',
        ),
        createProcess = lib.lookupFunction<
            Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Void>, Pointer<Void>, Int32,
                Uint32, Pointer<Void>, Pointer<Utf16>, Pointer<Void>, Pointer<_ProcessInformation>),
            int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Void>, Pointer<Void>, int, int,
                Pointer<Void>, Pointer<Utf16>, Pointer<Void>,
                Pointer<_ProcessInformation>)>('CreateProcessW'),
        writeFile = lib.lookupFunction<
            Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Uint32>, Pointer<Void>),
            int Function(int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Void>)>('WriteFile'),
        readFile = lib.lookupFunction<
            Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Uint32>, Pointer<Void>),
            int Function(int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Void>)>('ReadFile'),
        waitForSingleObject = lib.lookupFunction<Uint32 Function(IntPtr, Uint32),
            int Function(int, int)>('WaitForSingleObject'),
        getExitCodeProcess = lib.lookupFunction<Int32 Function(IntPtr, Pointer<Uint32>),
            int Function(int, Pointer<Uint32>)>('GetExitCodeProcess'),
        terminateProcess = lib.lookupFunction<Int32 Function(IntPtr, Uint32),
            int Function(int, int)>('TerminateProcess'),
        getLastError =
            lib.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  static final _Kernel32 instance = _Kernel32._(DynamicLibrary.open('kernel32.dll'));

  final int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, int) createPipe;
  final int Function(int) closeHandle;
  final int Function(_Coord, int, int, int, Pointer<IntPtr>) createPseudoConsole;
  final int Function(int, _Coord) resizePseudoConsole;
  final void Function(int) closePseudoConsole;
  final int Function(Pointer<Void>, int, int, Pointer<IntPtr>)
      initializeProcThreadAttributeList;
  final int Function(Pointer<Void>, int, int, Pointer<Void>, int, Pointer<Void>,
      Pointer<IntPtr>) updateProcThreadAttribute;
  final void Function(Pointer<Void>) deleteProcThreadAttributeList;
  final int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Void>, Pointer<Void>, int, int,
      Pointer<Void>, Pointer<Utf16>, Pointer<Void>, Pointer<_ProcessInformation>) createProcess;
  final int Function(int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Void>) writeFile;
  final int Function(int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Void>) readFile;
  final int Function(int, int) waitForSingleObject;
  final int Function(int, Pointer<Uint32>) getExitCodeProcess;
  final int Function(int, int) terminateProcess;
  final int Function() getLastError;
}
