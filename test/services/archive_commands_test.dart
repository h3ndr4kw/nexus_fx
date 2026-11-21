import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/archive_commands.dart';

void main() {
  group('archiveKindOf', () {
    test('recognises tar and zip variants case-insensitively', () {
      expect(archiveKindOf('a.tar.gz'), ArchiveKind.tarGz);
      expect(archiveKindOf('A.TGZ'), ArchiveKind.tarGz);
      expect(archiveKindOf('a.tar'), ArchiveKind.tar);
      expect(archiveKindOf('a.tar.bz2'), ArchiveKind.tarBz2);
      expect(archiveKindOf('a.tar.xz'), ArchiveKind.tarXz);
      expect(archiveKindOf('a.zip'), ArchiveKind.zip);
    });

    test('returns null for other files', () {
      expect(archiveKindOf('a.gz'), isNull);
      expect(archiveKindOf('notes.txt'), isNull);
      expect(archiveKindOf('zip'), isNull);
    });
  });

  test('archiveBaseName strips the full archive suffix', () {
    expect(archiveBaseName('logs.tar.gz'), 'logs');
    expect(archiveBaseName('logs.tgz'), 'logs');
    expect(archiveBaseName('v1.2.zip'), 'v1.2');
    expect(archiveBaseName('.tar.gz'), 'extracted');
  });

  test('shQuote survives quotes, dollars and backticks', () {
    expect(shQuote('plain'), "'plain'");
    expect(shQuote("it's"), "'it'\\''s'");
    expect(shQuote(r'$(rm -rf ~) `x` "y"'), r"""'$(rm -rf ~) `x` "y"'""");
  });

  group('defaultArchiveName', () {
    test('uses the folder name or the file name without extension', () {
      expect(
        defaultArchiveName(
          [const ArchiveSource('logs', isDir: true)],
          currentDirName: 'var',
          format: FileExplorerArchiveFormat.tarGz,
          existing: const {},
        ),
        'logs.tar.gz',
      );
      expect(
        defaultArchiveName(
          [const ArchiveSource('report.csv', isDir: false)],
          currentDirName: 'var',
          format: FileExplorerArchiveFormat.zip,
          existing: const {},
        ),
        'report.zip',
      );
    });

    test('uses the current folder for several items and avoids clashes', () {
      expect(
        defaultArchiveName(
          [
            const ArchiveSource('a', isDir: false),
            const ArchiveSource('b', isDir: false),
          ],
          currentDirName: 'tmp',
          format: FileExplorerArchiveFormat.tarGz,
          existing: const {'tmp.tar.gz', 'tmp (2).tar.gz'},
        ),
        'tmp (3).tar.gz',
      );
    });

    test('falls back to "archive" at the root', () {
      expect(
        defaultArchiveName(
          [
            const ArchiveSource('a', isDir: false),
            const ArchiveSource('b', isDir: false),
          ],
          currentDirName: '',
          format: FileExplorerArchiveFormat.zip,
          existing: const {},
        ),
        'archive.zip',
      );
    });
  });

  test('uniqueName appends a counter until the name is free', () {
    expect(uniqueName('logs', const {}), 'logs');
    expect(uniqueName('logs', const {'logs'}), 'logs (2)');
  });

  group('remote commands', () {
    test('compress cds into the folder and quotes every name', () {
      expect(
        remoteCompressCommand(
          dir: '/var/log',
          names: const ['nginx', "it's", '-rf'],
          archiveName: 'out.tar.gz',
          format: FileExplorerArchiveFormat.tarGz,
        ),
        "cd '/var/log' || exit 1; tar -czf 'out.tar.gz' 'nginx' 'it'\\''s' './-rf'"
        " || { rc=\$?; rm -f 'out.tar.gz'; exit \$rc; }",
      );
      expect(
        remoteCompressCommand(
          dir: '/srv',
          names: const ['a b'],
          archiveName: 'x.zip',
          format: FileExplorerArchiveFormat.zip,
        ),
        "cd '/srv' || exit 1; zip -r -q 'x.zip' 'a b'"
        " || { rc=\$?; rm -f 'x.zip'; exit \$rc; }",
      );
    });

    test('extract creates the target folder and picks the right tool', () {
      expect(
        remoteExtractCommand(
          archivePath: '/srv/a.tar.gz',
          destDir: '/srv/a',
          kind: ArchiveKind.tarGz,
        ),
        "mkdir '/srv/a' || exit 1; tar -xzf '/srv/a.tar.gz' -C '/srv/a'"
        " || { rc=\$?; rm -rf '/srv/a'; exit \$rc; }",
      );
      expect(
        remoteExtractCommand(
          archivePath: '/srv/a.tar.xz',
          destDir: '/srv/a',
          kind: ArchiveKind.tarXz,
        ),
        "mkdir '/srv/a' || exit 1; tar -xJf '/srv/a.tar.xz' -C '/srv/a'"
        " || { rc=\$?; rm -rf '/srv/a'; exit \$rc; }",
      );
      expect(
        remoteExtractCommand(
          archivePath: '/srv/a.zip',
          destDir: '/srv/a',
          kind: ArchiveKind.zip,
        ),
        "mkdir '/srv/a' || exit 1; unzip -q -o '/srv/a.zip' -d '/srv/a'"
        " || { rc=\$?; rm -rf '/srv/a'; exit \$rc; }",
      );
    });

    test('wrapWithExitCode and parseExitCode round-trip the status', () {
      final wrapped = wrapWithExitCode('tar -czf x y');
      expect(wrapped, contains('tar -czf x y'));
      expect(parseExitCode('${ArchiveCommandResult.marker}0\n'),
          const ArchiveCommandResult(0, ''));
      expect(
        parseExitCode('tar: y: Cannot stat\n${ArchiveCommandResult.marker}2\n'),
        const ArchiveCommandResult(2, 'tar: y: Cannot stat'),
      );
      expect(parseExitCode('garbage').exitCode, isNull);
    });

    test('describeRemoteFailure names the missing tool', () {
      expect(
        describeRemoteFailure(
          const ArchiveCommandResult(127, 'bash: zip: command not found'),
          'zip',
        ),
        contains("'zip' is not installed"),
      );
      expect(
        describeRemoteFailure(const ArchiveCommandResult(2, 'tar: boom'), 'tar'),
        'tar: boom',
      );
    });
  });

  group('local archives', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('nexus_archive_test');
      final src = Directory('${tmp.path}${Platform.pathSeparator}src');
      await Directory('${src.path}${Platform.pathSeparator}sub').create(recursive: true);
      await File('${src.path}${Platform.pathSeparator}sub${Platform.pathSeparator}a.txt')
          .writeAsString('hello');
      await File('${src.path}${Platform.pathSeparator}b.txt').writeAsString('world');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    for (final format in FileExplorerArchiveFormat.values) {
      test('compresses and extracts a folder as ${format.label}', () async {
        final sep = Platform.pathSeparator;
        final archiveName = 'out${format.extension}';
        await compressLocalArchive(
          dir: tmp.path,
          names: const ['src'],
          archiveName: archiveName,
          format: format,
        );
        final archive = File('${tmp.path}$sep$archiveName');
        expect(await archive.exists(), isTrue);

        final dest = '${tmp.path}${sep}restored';
        await extractLocalArchive(
          archivePath: archive.path,
          destDir: dest,
          kind: archiveKindOf(archiveName)!,
        );
        expect(
          await File('$dest${sep}src${sep}sub${sep}a.txt').readAsString(),
          'hello',
        );
        expect(await File('$dest${sep}src${sep}b.txt').readAsString(), 'world');
      });
    }

    test('reports a failure with the tool output', () async {
      await expectLater(
        extractLocalArchive(
          archivePath: '${tmp.path}${Platform.pathSeparator}missing.tar.gz',
          destDir: '${tmp.path}${Platform.pathSeparator}out',
          kind: ArchiveKind.tarGz,
        ),
        throwsA(isA<ArchiveOperationException>()),
      );
    });
  });
}
