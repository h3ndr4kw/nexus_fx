import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/playbook_models.dart';

/// Exception thrown when parsing a docx playbook archive or XML fails.
class PlaybookParseException implements Exception {
  final String message;

  PlaybookParseException(this.message);

  @override
  String toString() => 'PlaybookParseException: $message';
}

class PlaybookParser {
  static String _extractFilename(String filePath) {
    if (filePath.isEmpty) return 'Untitled';
    final normalized = filePath.replaceAll('\\', '/');
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isNotEmpty ? segments.last : 'Untitled';
  }

  /// Parses Markdown content into a structured [PlaybookDocument].
  /// Fenced code blocks (```sh, ```bash, etc.) become [PlaybookBlockType.scriptCell],
  /// headings (#, ##, etc.) become [PlaybookBlockType.heading],
  /// and paragraphs become [PlaybookBlockType.text].
  static PlaybookDocument parseMarkdown(String filePath, String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');

    final blocks = <PlaybookBlock>[];
    int blockCounter = 0;
    bool inCodeBlock = false;
    final currentCodeLines = <String>[];
    final currentTextLines = <String>[];

    void flushText() {
      if (currentTextLines.isNotEmpty) {
        while (currentTextLines.isNotEmpty && currentTextLines.first.trim().isEmpty) {
          currentTextLines.removeAt(0);
        }
        while (currentTextLines.isNotEmpty && currentTextLines.last.trim().isEmpty) {
          currentTextLines.removeLast();
        }
        if (currentTextLines.isNotEmpty) {
          blocks.add(
            PlaybookBlock(
              id: 'block_${blockCounter++}',
              type: PlaybookBlockType.text,
              content: currentTextLines.join('\n'),
            ),
          );
        }
        currentTextLines.clear();
      }
    }

    final headingRegex = RegExp(r'^(#{1,6})\s+(.*)$');

    for (final line in lines) {
      if (inCodeBlock) {
        if (line.trim().startsWith('```')) {
          inCodeBlock = false;
          while (currentCodeLines.isNotEmpty && currentCodeLines.last.trim().isEmpty) {
            currentCodeLines.removeLast();
          }
          blocks.add(
            PlaybookBlock(
              id: 'block_${blockCounter++}',
              type: PlaybookBlockType.scriptCell,
              content: currentCodeLines.join('\n'),
            ),
          );
          currentCodeLines.clear();
        } else {
          currentCodeLines.add(line);
        }
      } else {
        if (line.trim().startsWith('```')) {
          flushText();
          inCodeBlock = true;
          currentCodeLines.clear();
        } else {
          final headingMatch = headingRegex.firstMatch(line.trim());
          if (headingMatch != null) {
            flushText();
            final level = headingMatch.group(1)!.length;
            final headingText = headingMatch.group(2)!.trim();
            blocks.add(
              PlaybookBlock(
                id: 'block_${blockCounter++}',
                type: PlaybookBlockType.heading,
                headingLevel: level,
                content: headingText,
              ),
            );
          } else if (line.trim().isEmpty) {
            flushText();
          } else {
            currentTextLines.add(line);
          }
        }
      }
    }

    if (inCodeBlock) {
      while (currentCodeLines.isNotEmpty && currentCodeLines.last.trim().isEmpty) {
        currentCodeLines.removeLast();
      }
      blocks.add(
        PlaybookBlock(
          id: 'block_${blockCounter++}',
          type: PlaybookBlockType.scriptCell,
          content: currentCodeLines.join('\n'),
        ),
      );
    } else {
      flushText();
    }

    String title = '';
    for (final block in blocks) {
      if (block.type == PlaybookBlockType.heading && block.headingLevel == 1) {
        if (block.content.trim().isNotEmpty) {
          title = block.content.trim();
          break;
        }
      }
    }
    if (title.isEmpty) {
      for (final block in blocks) {
        if (block.type == PlaybookBlockType.heading) {
          if (block.content.trim().isNotEmpty) {
            title = block.content.trim();
            break;
          }
        }
      }
    }
    if (title.isEmpty) {
      title = _extractFilename(filePath);
    }

    return PlaybookDocument(
      filePath: filePath,
      title: title,
      blocks: blocks,
    );
  }

  /// Parses plain script files (.sh, .bash, .conf, .txt) as script cells.
  static PlaybookDocument parseScript(String filePath, String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();
    final filename = _extractFilename(filePath);
    final block = PlaybookBlock(
      id: 'block_0',
      type: PlaybookBlockType.scriptCell,
      content: normalized,
    );
    return PlaybookDocument(
      filePath: filePath,
      title: filename,
      blocks: [block],
    );
  }

  /// Serializes a [PlaybookDocument] back to Markdown string.
  static String serializeToMarkdown(PlaybookDocument doc) {
    final buffer = StringBuffer();
    for (var i = 0; i < doc.blocks.length; i++) {
      final block = doc.blocks[i];
      if (i > 0) {
        buffer.write('\n\n');
      }
      switch (block.type) {
        case PlaybookBlockType.heading:
          final level = block.headingLevel.clamp(1, 6);
          final hashes = '#' * level;
          buffer.write('$hashes ${block.content}');
          break;
        case PlaybookBlockType.text:
          buffer.write(block.content);
          break;
        case PlaybookBlockType.scriptCell:
          buffer.write('```sh\n${block.content.trimRight()}\n```');
          break;
      }
    }
    return buffer.toString();
  }

  static String _extractParagraphText(XmlElement p) {
    final buffer = StringBuffer();
    for (final node in p.descendants) {
      if (node is XmlElement) {
        if (node.name.local == 't') {
          buffer.write(node.innerText);
        } else if (node.name.local == 'tab') {
          buffer.write('\t');
        } else if (node.name.local == 'br') {
          buffer.write('\n');
        }
      }
    }
    return buffer.toString();
  }

  static (bool, int) _checkHeading(XmlElement p) {
    final pStyles = p.descendants.whereType<XmlElement>().where((e) => e.name.local == 'pStyle');
    for (final pStyle in pStyles) {
      for (final attr in pStyle.attributes) {
        final val = attr.value;
        final lower = val.toLowerCase();
        if (lower.contains('heading') || lower.contains('title')) {
          int level = 1;
          final match = RegExp(r'heading\s*(\d+)', caseSensitive: false).firstMatch(val);
          if (match != null) {
            level = int.tryParse(match.group(1)!) ?? 1;
          } else if (lower.contains('subtitle')) {
            level = 2;
          }
          return (true, level.clamp(1, 6));
        }
      }
    }
    return (false, 1);
  }

  static bool _isCodeParagraph(XmlElement p) {
    const codeFonts = [
      'consolas',
      'courier',
      'source code',
      'lucida console',
      'monaco',
      'menlo',
      'monospace',
      'dejavu sans mono',
      'fira code',
      'cascadia',
      'jetbrains mono',
      'inconsolata',
      'ubuntu mono',
      'sf mono',
      'roboto mono',
    ];

    final rFontsElements = p.descendants.whereType<XmlElement>().where((e) => e.name.local == 'rFonts');
    for (final rFonts in rFontsElements) {
      for (final attr in rFonts.attributes) {
        final val = attr.value.toLowerCase();
        for (final font in codeFonts) {
          if (val.contains(font)) {
            return true;
          }
        }
      }
    }

    const codeStyles = ['code', 'script', 'command', 'terminal', 'console', 'verbatim'];
    final styleElements = p.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'pStyle' || e.name.local == 'rStyle',
    );
    for (final style in styleElements) {
      for (final attr in style.attributes) {
        final val = attr.value.toLowerCase();
        for (final s in codeStyles) {
          if (val.contains(s)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /// Parses DOCX file bytes into a structured [PlaybookDocument].
  ///
  /// Extracts headings from paragraphs styled with Heading/Title,
  /// bundles contiguous monospace font runs/styles into [PlaybookBlockType.scriptCell],
  /// and emits other paragraphs as [PlaybookBlockType.text].
  /// Throws [PlaybookParseException] if the archive is invalid or word/document.xml is missing.
  static PlaybookDocument parseDocx(String filePath, List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      ArchiveFile? docFile;
      for (final file in archive.files) {
        final normalizedName = file.name.replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
        if (normalizedName == 'word/document.xml') {
          docFile = file;
          break;
        }
      }
      if (docFile == null) {
        throw PlaybookParseException('word/document.xml missing from docx archive');
      }

      final contentBytes = docFile.content;
      if (contentBytes.isEmpty) {
        throw PlaybookParseException('word/document.xml is empty');
      }

      final xmlString = utf8.decode(contentBytes, allowMalformed: true);
      final xmlDoc = XmlDocument.parse(xmlString);

      final blocks = <PlaybookBlock>[];
      int blockCounter = 0;
      final currentCodeLines = <String>[];

      void flushCode() {
        if (currentCodeLines.isNotEmpty) {
          while (currentCodeLines.isNotEmpty && currentCodeLines.last.trim().isEmpty) {
            currentCodeLines.removeLast();
          }
          if (currentCodeLines.isNotEmpty) {
            blocks.add(
              PlaybookBlock(
                id: 'block_${blockCounter++}',
                type: PlaybookBlockType.scriptCell,
                content: currentCodeLines.join('\n'),
              ),
            );
          }
          currentCodeLines.clear();
        }
      }

      final pElements = xmlDoc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p');

      for (final p in pElements) {
        final (isHeading, headingLevel) = _checkHeading(p);
        final text = _extractParagraphText(p);

        if (isHeading) {
          flushCode();
          if (text.trim().isNotEmpty) {
            blocks.add(
              PlaybookBlock(
                id: 'block_${blockCounter++}',
                type: PlaybookBlockType.heading,
                headingLevel: headingLevel,
                content: text.trim(),
              ),
            );
          }
        } else if (_isCodeParagraph(p)) {
          currentCodeLines.add(text);
        } else {
          flushCode();
          if (text.trim().isNotEmpty) {
            blocks.add(
              PlaybookBlock(
                id: 'block_${blockCounter++}',
                type: PlaybookBlockType.text,
                content: text.trim(),
              ),
            );
          }
        }
      }

      flushCode();

      String title = '';
      for (final block in blocks) {
        if (block.type == PlaybookBlockType.heading && block.content.trim().isNotEmpty) {
          title = block.content.trim();
          break;
        }
      }
      if (title.isEmpty) {
        title = _extractFilename(filePath);
      }

      return PlaybookDocument(
        filePath: filePath,
        title: title,
        blocks: blocks,
      );
    } on PlaybookParseException {
      rethrow;
    } catch (e) {
      throw PlaybookParseException('Failed to parse docx document: $e');
    }
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Serializes a [PlaybookDocument] into `.docx` archive bytes.
  /// If [existingBytes] is provided and valid, preserves all other archive entries
  /// in the `.docx` container and updates `word/document.xml`.
  static List<int> serializeToDocx(
    PlaybookDocument doc, {
    List<int>? existingBytes,
  }) {
    final bodyBuf = StringBuffer();
    bodyBuf.writeln(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
    );
    bodyBuf.writeln(
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
    );
    bodyBuf.writeln('  <w:body>');

    for (final block in doc.blocks) {
      switch (block.type) {
        case PlaybookBlockType.heading:
          final level = block.headingLevel.clamp(1, 6);
          final escaped = _escapeXml(block.content);
          bodyBuf.writeln('    <w:p>');
          bodyBuf.writeln('      <w:pPr><w:pStyle w:val="Heading$level"/></w:pPr>');
          bodyBuf.writeln('      <w:r><w:t xml:space="preserve">$escaped</w:t></w:r>');
          bodyBuf.writeln('    </w:p>');
          break;
        case PlaybookBlockType.text:
          final lines = block.content.replaceAll('\r\n', '\n').split('\n');
          for (final line in lines) {
            final escaped = _escapeXml(line);
            bodyBuf.writeln('    <w:p>');
            bodyBuf.writeln('      <w:r><w:t xml:space="preserve">$escaped</w:t></w:r>');
            bodyBuf.writeln('    </w:p>');
          }
          break;
        case PlaybookBlockType.scriptCell:
          final lines = block.content.replaceAll('\r\n', '\n').split('\n');
          for (final line in lines) {
            final escaped = _escapeXml(line);
            bodyBuf.writeln('    <w:p>');
            bodyBuf.writeln('      <w:r>');
            bodyBuf.writeln('        <w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/></w:rPr>');
            bodyBuf.writeln('        <w:t xml:space="preserve">$escaped</w:t>');
            bodyBuf.writeln('      </w:r>');
            bodyBuf.writeln('    </w:p>');
          }
          break;
      }
    }

    bodyBuf.writeln('  </w:body>');
    bodyBuf.writeln('</w:document>');

    final xmlBytes = utf8.encode(bodyBuf.toString());
    final newArchive = Archive();

    if (existingBytes != null && existingBytes.isNotEmpty) {
      try {
        final oldArchive = ZipDecoder().decodeBytes(existingBytes, verify: false);
        var replaced = false;
        for (final file in oldArchive.files) {
          final normalizedName = file.name
              .replaceAll('\\', '/')
              .replaceFirst(RegExp(r'^/'), '');
          if (normalizedName == 'word/document.xml') {
            newArchive.addFile(
              ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes),
            );
            replaced = true;
          } else {
            newArchive.addFile(file);
          }
        }
        if (!replaced) {
          newArchive.addFile(
            ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes),
          );
        }
        return ZipEncoder().encode(newArchive);
      } catch (_) {
        // Fall through to fresh archive creation
      }
    }

    newArchive.addFile(
      ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes),
    );
    return ZipEncoder().encode(newArchive);
  }
}
