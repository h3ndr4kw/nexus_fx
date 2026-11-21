import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/file_explorer_models.dart';
import 'app_log.dart';
import 'app_paths.dart';
import 'transfer_control.dart';

/// File operations on this machine's disk for the local pane: listing,
/// create/delete/rename, and copy/move with progress, pause and cancel.
class LocalFileOperations {
  Future<List<FileExplorerItem>> listLocal(String dirPath, {String filter = ''}) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return listLocal(AppPaths.defaultLocalDir, filter: filter);
    }

    final items = <FileExplorerItem>[];
    final filterLower = filter.trim().toLowerCase();

    try {
      final entries = await dir.list().toList();
      for (final entity in entries) {
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments[entity.uri.pathSegments.length - (entity.uri.pathSegments.last.isEmpty ? 2 : 1)]
            : entity.path;

        if (filterLower.isNotEmpty && !name.toLowerCase().contains(filterLower)) {
          continue;
        }

        final isDir = entity is Directory;
        int size = 0;
        DateTime? modTime;

        try {
          final stat = await entity.stat();
          size = stat.size;
          modTime = stat.modified;
        } catch (_) {}

        final modStr = modTime != null
            ? FileExplorerItem.formatDateTime(modTime)
            : 'Unknown';

        items.add(FileExplorerItem(
          name: name,
          path: entity.path,
          isDir: isDir,
          size: size,
          modified: isDir ? '- -' : modStr,
          modifiedDateTime: modTime,
        ));
      }

      // Sort: dirs first, then alphabetically
      items.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Add parent directory ".." if parent exists and no active filter
      final parent = dir.parent;
      if (filterLower.isEmpty && parent.path != dir.path) {
        items.insert(0, FileExplorerItem.parentDir(parent.path));
      }
    } catch (e) {
      debugPrint('Error listing local files in $dirPath: $e');
      rethrow;
    }

    return items;
  }

  Future<void> createLocalFile(String dirPath, String fileName) async {
    final file = File('$dirPath${Platform.pathSeparator}$fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
  }

  Future<void> createLocalDir(String dirPath, String dirName) async {
    final dir = Directory('$dirPath${Platform.pathSeparator}$dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<void> deleteLocal(String targetPath) async {
    final type = await FileSystemEntity.type(targetPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(targetPath).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(targetPath).delete();
    }
  }

  Future<void> renameLocal(String oldPath, String newName) async {
    final file = File(oldPath);
    final isDir = await Directory(oldPath).exists();
    final parent = File(oldPath).parent.path;
    final newPath = '$parent${Platform.pathSeparator}$newName';

    if (isDir) {
      await Directory(oldPath).rename(newPath);
    } else {
      await file.rename(newPath);
    }
  }

  /// Copies [srcPath] into [destDirPath], named [destName] if given (else
  /// the source name).
  Future<void> copyLocal(
    String srcPath,
    String destDirPath, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    String? destName,
  }) async {
    final name = destName ?? srcPath.split(Platform.pathSeparator).last;
    final destPath = '$destDirPath${Platform.pathSeparator}$name';
    final isDir = await Directory(srcPath).exists();
    final agg = onProgress == null
        ? null
        : TransferProgressAggregator(await localSize(srcPath), onProgress);

    if (isDir) {
      await _copyDirLocal(Directory(srcPath), Directory(destPath), agg, cancelToken);
    } else {
      await File(destPath).parent.create(recursive: true);
      await _copyFileLocal(File(srcPath), File(destPath), agg?.forFile(), cancelToken);
    }
  }

  Future<void> _copyFileLocal(
    File src,
    File dest,
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
  ) async {
    final totalBytes = await src.length();
    final sink = dest.openWrite();
    var sent = 0;
    var ok = false;
    try {
      await for (final chunk in src.openRead()) {
        cancelToken?.throwIfCancelled();
        if (cancelToken?.isPaused ?? false) await cancelToken!.waitIfPaused();
        sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent, totalBytes);
      }
      await sink.flush();
      ok = true;
    } finally {
      await sink.close();
      if (!ok) {
        try {
          await dest.delete();
        } catch (e, st) {
          AppLog.warning('FileExplorer: deleting partial local copy', e, st);
        }
      }
    }
  }

  Future<void> _copyDirLocal(
    Directory src,
    Directory dest,
    TransferProgressAggregator? agg,
    TransferCancelToken? cancelToken,
  ) async {
    if (!await dest.exists()) {
      await dest.create(recursive: true);
    }
    await for (final entity in src.list(recursive: false)) {
      final entityName = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments[entity.uri.pathSegments.length - (entity.uri.pathSegments.last.isEmpty ? 2 : 1)]
          : entity.path;
      final newDest = '${dest.path}${Platform.pathSeparator}$entityName';
      if (entity is Directory) {
        await _copyDirLocal(entity, Directory(newDest), agg, cancelToken);
      } else if (entity is File) {
        await _copyFileLocal(entity, File(newDest), agg?.forFile(), cancelToken);
      }
    }
  }

  /// Total size in bytes of a local file or directory tree.
  Future<int> localSize(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.file) return await File(path).length();
    if (type != FileSystemEntityType.directory) return 0;
    var total = 0;
    await for (final e in Directory(path).list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<void> moveLocal(
    String srcPath,
    String destDirPath, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    String? destName,
  }) async {
    final name = destName ?? srcPath.split(Platform.pathSeparator).last;
    final destPath = '$destDirPath${Platform.pathSeparator}$name';
    try {
      // Same-volume rename: atomic and instant.
      if (await Directory(srcPath).exists()) {
        await Directory(srcPath).rename(destPath);
      } else {
        await File(srcPath).rename(destPath);
      }
      onProgress?.call(1, 1);
    } catch (_) {
      // Cross-volume: copy (with progress) then delete.
      await copyLocal(
        srcPath,
        destDirPath,
        onProgress: onProgress,
        cancelToken: cancelToken,
        destName: destName,
      );
      await deleteLocal(srcPath);
    }
  }

  Future<String> readLocalText(String filePath) async {
    final file = File(filePath);
    return await file.readAsString();
  }

  Future<Uint8List> readLocalBytes(String filePath) => File(filePath).readAsBytes();

  Future<void> writeLocalText(String filePath, String content) async {
    final file = File(filePath);
    await file.writeAsString(content);
  }

  Future<void> mergeLocal(List<String> srcPaths, String destDirPath, String newFileName) async {
    final outFile = File('$destDirPath${Platform.pathSeparator}$newFileName');
    final sink = outFile.openWrite();
    try {
      for (int i = 0; i < srcPaths.length; i++) {
        final f = File(srcPaths[i]);
        if (await f.exists()) {
          final stream = f.openRead();
          await sink.addStream(stream);
          if (i < srcPaths.length - 1) {
            sink.writeln();
          }
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }
}
