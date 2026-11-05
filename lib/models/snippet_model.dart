
/// Model representing a reusable command snippet in Nexus FX.
class SnippetItem {
  final String id;
  final String name;
  final String description;
  final List<String> commands;
  final DateTime modifiedAt;

  SnippetItem({
    required this.id,
    required this.name,
    this.description = '',
    required this.commands,
    DateTime? modifiedAt,
  }) : modifiedAt = modifiedAt ?? DateTime.now();

  /// Returns commands combined into a single multiline script string.
  String get fullScript => commands.join('\n');

  /// Total number of lines across all commands.
  int get lineCount => commands.fold<int>(
        0,
        (acc, cmd) => acc + (cmd.split('\n').where((l) => l.trim().isNotEmpty).length),
      );

  SnippetItem copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? commands,
    DateTime? modifiedAt,
  }) {
    return SnippetItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      commands: commands ?? List<String>.from(this.commands),
      modifiedAt: modifiedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'commands': commands,
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  factory SnippetItem.fromJson(Map<String, dynamic> json) {
    final rawCommands = json['commands'];
    List<String> parsedCommands = [];
    if (rawCommands is List) {
      parsedCommands = rawCommands.map((e) => e.toString()).toList();
    } else if (rawCommands is String && rawCommands.isNotEmpty) {
      parsedCommands = [rawCommands];
    }

    return SnippetItem(
      id: json['id'] as String? ?? 'snip_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Untitled Snippet',
      description: json['description'] as String? ?? '',
      commands: parsedCommands,
      modifiedAt: DateTime.tryParse(json['modifiedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  String toString() => 'SnippetItem(id: $id, name: $name, commands: ${commands.length})';
}
