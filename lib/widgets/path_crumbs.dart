/// One clickable segment of a pane's path bar.
class PathCrumb {
  const PathCrumb(this.label, this.path);
  final String label;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is PathCrumb && other.label == label && other.path == path;

  @override
  int get hashCode => Object.hash(label, path);

  @override
  String toString() => 'PathCrumb($label, $path)';
}

/// Splits [path] into cumulative segments, root first. [windowsStyle] accepts both
/// `\` and `/` and treats a leading `C:` as the root; otherwise paths are POSIX.
List<PathCrumb> splitPathCrumbs(String path, {required bool windowsStyle}) {
  const bs = '\\';
  final parts = path
      .split(windowsStyle ? RegExp('[\\\\/]') : '/')
      .where((s) => s.isNotEmpty)
      .toList();
  if (windowsStyle) {
    if (parts.isEmpty) return const [];
    final root = parts.first.endsWith(':') ? '${parts.first}$bs' : parts.first;
    final crumbs = <PathCrumb>[PathCrumb(parts.first, root)];
    var acc = root.endsWith(bs) ? root : '$root$bs';
    for (var i = 1; i < parts.length; i++) {
      acc = i == 1 ? '$acc${parts[i]}' : '$acc$bs${parts[i]}';
      crumbs.add(PathCrumb(parts[i], acc));
    }
    return crumbs;
  }
  final crumbs = <PathCrumb>[const PathCrumb('/', '/')];
  var acc = '';
  for (final part in parts) {
    acc = '$acc/$part';
    crumbs.add(PathCrumb(part, acc));
  }
  return crumbs;
}
