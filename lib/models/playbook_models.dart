enum PlaybookBlockType {
  heading,
  text,
  scriptCell,
}

class PlaybookBlock {
  final String id;
  PlaybookBlockType type;
  int headingLevel;
  String content;
  String? targetNodeOverride;
  DateTime? lastExecutedTime;
  String? lastExecutedTarget;

  PlaybookBlock({
    required this.id,
    required this.type,
    this.headingLevel = 1,
    this.content = '',
    this.targetNodeOverride,
    this.lastExecutedTime,
    this.lastExecutedTarget,
  });

  List<String> get lines {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalized.split('\n');
    while (rawLines.isNotEmpty && rawLines.last.trim().isEmpty) {
      rawLines.removeLast();
    }
    return rawLines;
  }

  PlaybookBlock copyWith({
    String? id,
    PlaybookBlockType? type,
    int? headingLevel,
    String? content,
    String? targetNodeOverride,
    bool clearTargetNodeOverride = false,
    DateTime? lastExecutedTime,
    bool clearLastExecutedTime = false,
    String? lastExecutedTarget,
  }) {
    return PlaybookBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      headingLevel: headingLevel ?? this.headingLevel,
      content: content ?? this.content,
      targetNodeOverride: clearTargetNodeOverride
          ? null
          : (targetNodeOverride ?? this.targetNodeOverride),
      lastExecutedTime: clearLastExecutedTime
          ? null
          : (lastExecutedTime ?? this.lastExecutedTime),
      lastExecutedTarget: clearLastExecutedTime
          ? null
          : (lastExecutedTarget ?? this.lastExecutedTarget),
    );
  }
}

class PlaybookDocument {
  final String filePath;
  final String title;
  final List<PlaybookBlock> blocks;
  bool isModified;

  PlaybookDocument({
    required this.filePath,
    required this.title,
    required this.blocks,
    this.isModified = false,
  });

  PlaybookDocument copyWith({
    String? filePath,
    String? title,
    List<PlaybookBlock>? blocks,
    bool? isModified,
  }) {
    return PlaybookDocument(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
      isModified: isModified ?? this.isModified,
    );
  }
}
