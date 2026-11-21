import 'dart:io';

import '../models/file_explorer_models.dart';

/// Archive types the File Explorer can extract.
enum ArchiveKind { tarGz, tar, tarBz2, tarXz, zip }

const _suffixes = <String, ArchiveKind>{
  '.tar.gz': ArchiveKind.tarGz,
  '.tgz': ArchiveKind.tarGz,
  '.tar.bz2': ArchiveKind.tarBz2,
  '.tbz2': ArchiveKind.tarBz2,
  '.tbz': ArchiveKind.tarBz2,
  '.tar.xz': ArchiveKind.tarXz,
  '.txz': ArchiveKind.tarXz,
  '.tar': ArchiveKind.tar,
  '.zip': ArchiveKind.zip,
};

String? _matchingSuffix(String fileName) {
  final lower = fileName.toLowerCase();
  for (final suffix in _suffixes.keys) {
    if (lower.length > suffix.length && lower.endsWith(suffix)) return suffix;
  }
  return null;
}

ArchiveKind? archiveKindOf(String fileName) {
  final suffix = _matchingSuffix(fileName);
  return suffix == null ? null : _suffixes[suffix];
}

/// [fileName] without its archive suffix, used as the extract folder name.
String archiveBaseName(String fileName) {
  final suffix = _matchingSuffix(fileName);
  if (suffix == null) return 'extracted';
  return fileName.substring(0, fileName.length - suffix.length);
}

/// Quotes [value] for a POSIX shell so no character in it is interpreted.
String shQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// A name that would read as an option to tar or zip gets a `./` prefix.
String _safeOperand(String name) => name.startsWith('-') ? './$name' : name;

/// `name` if it is not in [existing], otherwise `name (2)`, `name (3)`, ...
String uniqueName(String name, Set<String> existing, {String suffix = ''}) {
  if (!existing.contains('$name$suffix')) return '$name$suffix';
  var n = 2;
  while (existing.contains('$name ($n)$suffix')) {
    n++;
  }
  return '$name ($n)$suffix';
}

class ArchiveSource {
  final String name;
  final bool isDir;

  const ArchiveSource(this.name, {required this.isDir});
}

/// Suggested archive name for [sources]: the item's own name for a single
/// item, otherwise the folder they sit in.
String defaultArchiveName(
  List<ArchiveSource> sources, {
  required String currentDirName,
  required FileExplorerArchiveFormat format,
  required Set<String> existing,
}) {
  String base;
  if (sources.length == 1) {
    final only = sources.first;
    final dot = only.name.lastIndexOf('.');
    base = only.isDir || dot <= 0 ? only.name : only.name.substring(0, dot);
  } else {
    base = currentDirName.isEmpty ? 'archive' : currentDirName;
  }
  return uniqueName(base, existing, suffix: format.extension);
}

/// Shell command that archives [names] (relative to [dir]) into
/// [archiveName] inside [dir]. A failed run removes the partial archive.
String remoteCompressCommand({
  required String dir,
  required List<String> names,
  required String archiveName,
  required FileExplorerArchiveFormat format,
}) {
  final operands = names.map((n) => shQuote(_safeOperand(n))).join(' ');
  final archive = shQuote(archiveName);
  final tool = switch (format) {
    FileExplorerArchiveFormat.tarGz => 'tar -czf $archive $operands',
    FileExplorerArchiveFormat.zip => 'zip -r -q $archive $operands',
  };
  return 'cd ${shQuote(dir)} || exit 1; $tool'
      ' || { rc=\$?; rm -f $archive; exit \$rc; }';
}

/// Shell command that unpacks [archivePath] into the new folder [destDir].
/// `mkdir` without `-p` refuses an existing folder, so the cleanup on
/// failure only ever removes what this command created.
String remoteExtractCommand({
  required String archivePath,
  required String destDir,
  required ArchiveKind kind,
}) {
  final archive = shQuote(archivePath);
  final dest = shQuote(destDir);
  final tool = switch (kind) {
    ArchiveKind.tarGz => 'tar -xzf $archive -C $dest',
    ArchiveKind.tar => 'tar -xf $archive -C $dest',
    ArchiveKind.tarBz2 => 'tar -xjf $archive -C $dest',
    ArchiveKind.tarXz => 'tar -xJf $archive -C $dest',
    ArchiveKind.zip => 'unzip -q -o $archive -d $dest',
  };
  return 'mkdir $dest || exit 1; $tool'
      ' || { rc=\$?; rm -rf $dest; exit \$rc; }';
}

/// Program a remote command needs, for the "not installed" message.
String remoteToolFor({FileExplorerArchiveFormat? format, ArchiveKind? kind}) {
  if (format == FileExplorerArchiveFormat.zip) return 'zip';
  if (kind == ArchiveKind.zip) return 'unzip';
  return 'tar';
}

class ArchiveCommandResult {
  static const marker = '__NEXUS_RC__';

  /// Null when the marker never arrived (the command did not finish).
  final int? exitCode;
  final String output;

  const ArchiveCommandResult(this.exitCode, this.output);

  bool get ok => exitCode == 0;

  @override
  bool operator ==(Object other) =>
      other is ArchiveCommandResult &&
      other.exitCode == exitCode &&
      other.output == output;

  @override
  int get hashCode => Object.hash(exitCode, output);
}

/// Runs [cmd] in a subshell with stderr folded into stdout and prints its
/// exit status after a marker. The plain exec helpers drop the exit code
/// (and the FE hop and tmsh wrappers would hide it anyway).
String wrapWithExitCode(String cmd) =>
    '( $cmd ) 2>&1; echo "${ArchiveCommandResult.marker}\$?"';

ArchiveCommandResult parseExitCode(String output) {
  final at = output.lastIndexOf(ArchiveCommandResult.marker);
  if (at < 0) return ArchiveCommandResult(null, output.trim());
  final codeText = output
      .substring(at + ArchiveCommandResult.marker.length)
      .trim()
      .split(RegExp(r'\s'))
      .first;
  return ArchiveCommandResult(
    int.tryParse(codeText),
    output.substring(0, at).trim(),
  );
}

String describeRemoteFailure(ArchiveCommandResult result, String tool) {
  final notFound = result.exitCode == 127 ||
      RegExp('$tool: (command )?not found').hasMatch(result.output);
  if (notFound) return "'$tool' is not installed on this node.";
  if (result.output.isNotEmpty) return result.output;
  return result.exitCode == null
      ? 'the command did not finish'
      : 'exit code ${result.exitCode}';
}

class ArchiveOperationException implements Exception {
  final String message;

  const ArchiveOperationException(this.message);

  @override
  String toString() => message;
}

/// bsdtar: ships with Windows 10 1803+ and macOS, reads and writes zip too.
String? _bsdtarPath() {
  if (Platform.isWindows) {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final path = '$root\\System32\\tar.exe';
    return File(path).existsSync() ? path : null;
  }
  if (Platform.isMacOS) return '/usr/bin/tar';
  return null;
}

Future<void> _runLocal(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  final ProcessResult result;
  try {
    result = await Process.run(executable, args, workingDirectory: workingDirectory);
  } on ProcessException {
    throw ArchiveOperationException("'$executable' is not available on this computer.");
  }
  if (result.exitCode != 0) {
    final output = '${result.stderr}\n${result.stdout}'.trim();
    throw ArchiveOperationException(
      output.isEmpty ? '$executable exited with code ${result.exitCode}' : output,
    );
  }
}

String _requireTar() {
  if (Platform.isWindows) {
    return _bsdtarPath() ??
        (throw const ArchiveOperationException(
          'tar.exe was not found. It ships with Windows 10 version 1803 and later.',
        ));
  }
  return _bsdtarPath() ?? 'tar';
}

/// Archives [names] (relative to [dir]) into [archiveName] inside [dir].
Future<void> compressLocalArchive({
  required String dir,
  required List<String> names,
  required String archiveName,
  required FileExplorerArchiveFormat format,
}) async {
  final archivePath = '$dir${Platform.pathSeparator}$archiveName';
  if (await File(archivePath).exists() || await Directory(archivePath).exists()) {
    throw ArchiveOperationException("'$archiveName' already exists.");
  }
  final operands = names.map(_safeOperand).toList();
  try {
    switch (format) {
      case FileExplorerArchiveFormat.tarGz:
        await _runLocal(_requireTar(), ['-czf', archivePath, '-C', dir, ...operands]);
      case FileExplorerArchiveFormat.zip:
        final bsdtar = _bsdtarPath();
        if (bsdtar != null) {
          // -a picks the format from the .zip suffix.
          await _runLocal(bsdtar, ['-a', '-cf', archivePath, '-C', dir, ...operands]);
        } else {
          await _runLocal('zip', ['-r', '-q', archivePath, ...operands],
              workingDirectory: dir);
        }
    }
  } catch (_) {
    final partial = File(archivePath);
    if (await partial.exists()) await partial.delete();
    rethrow;
  }
}

/// Unpacks [archivePath] into the new folder [destDir].
Future<void> extractLocalArchive({
  required String archivePath,
  required String destDir,
  required ArchiveKind kind,
}) async {
  final dest = Directory(destDir);
  if (await dest.exists() || await File(destDir).exists()) {
    throw ArchiveOperationException("'$destDir' already exists.");
  }
  if (!await File(archivePath).exists()) {
    throw ArchiveOperationException("'$archivePath' does not exist.");
  }
  await dest.create();
  try {
    final bsdtar = _bsdtarPath();
    if (kind == ArchiveKind.zip && bsdtar == null) {
      await _runLocal('unzip', ['-q', '-o', archivePath, '-d', destDir]);
    } else {
      // bsdtar and GNU tar both detect the compression when reading.
      await _runLocal(bsdtar ?? 'tar', ['-xf', archivePath, '-C', destDir]);
    }
  } catch (_) {
    if (await dest.exists()) await dest.delete(recursive: true);
    rethrow;
  }
}
