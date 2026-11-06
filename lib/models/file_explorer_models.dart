import 'session_models.dart';
import '../services/session_manager_service.dart';

enum ExplorerTargetType {
  local,
  networkManager,
  oam,
  fe,
  customSsh,
  sessionSsh,
}

class ExplorerNodeTarget {
  final ExplorerTargetType type;
  final String label;
  final String host;
  final int port;
  final String username;
  final String password;
  final String? clusterName;
  final String? siteName;
  final bool isOam;
  final String? feHostname;
  final String? jumpHost;
  final int jumpPort;
  final String? jumpUsername;
  final String? jumpPassword;
  final String? sessionId;
  final String sshMacs;
  final String customSshOptions;

  const ExplorerNodeTarget({
    required this.type,
    required this.label,
    this.host = '127.0.0.1',
    this.port = 22,
    this.username = '',
    this.password = '',
    this.clusterName,
    this.siteName,
    this.isOam = false,
    this.feHostname,
    this.jumpHost,
    this.jumpPort = 22,
    this.jumpUsername,
    this.jumpPassword,
    this.sessionId,
    this.sshMacs = 'auto',
    this.customSshOptions = '',
  });

  bool get isLocal => type == ExplorerTargetType.local;
  bool get hasJumpHost => jumpHost != null && jumpHost!.isNotEmpty;

  bool isSameTarget(ExplorerNodeTarget other) {
    if (type != other.type) return false;
    if (isLocal && other.isLocal) return true;
    return host == other.host &&
        port == other.port &&
        username == other.username &&
        feHostname == other.feHostname &&
        sessionId == other.sessionId;
  }

  static const ExplorerNodeTarget local = ExplorerNodeTarget(
    type: ExplorerTargetType.local,
    label: 'Local Filesystem',
  );

  factory ExplorerNodeTarget.fromSessionProfile(
    SessionProfile profile, [
    ResolvedSshRoute? route,
  ]) {
    if (profile.protocol == SessionProtocol.local) {
      return ExplorerNodeTarget.local;
    }
    return ExplorerNodeTarget(
      type: ExplorerTargetType.sessionSsh,
      label: profile.name,
      host: profile.host,
      port: profile.port,
      username: profile.username,
      password: profile.password,
      jumpHost: route?.jumpHost,
      jumpPort: route?.jumpPort ?? 22,
      jumpUsername: route?.jumpUsername,
      jumpPassword: route?.jumpPassword,
      sessionId: profile.id,
      sshMacs: profile.sshMacs,
      customSshOptions: profile.customSshOptions,
    );
  }

  ExplorerNodeTarget copyWith({
    ExplorerTargetType? type,
    String? label,
    String? host,
    int? port,
    String? username,
    String? password,
    String? clusterName,
    String? siteName,
    bool? isOam,
    String? feHostname,
    String? sshMacs,
    String? customSshOptions,
  }) {
    return ExplorerNodeTarget(
      type: type ?? this.type,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      clusterName: clusterName ?? this.clusterName,
      siteName: siteName ?? this.siteName,
      isOam: isOam ?? this.isOam,
      feHostname: feHostname ?? this.feHostname,
      sshMacs: sshMacs ?? this.sshMacs,
      customSshOptions: customSshOptions ?? this.customSshOptions,
    );
  }
}

class FileExplorerItem {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final String modified;
  final DateTime? modifiedDateTime;
  bool isSelected;

  FileExplorerItem({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.modified,
    this.modifiedDateTime,
    this.isSelected = false,
  });

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final m = months[dt.month - 1];
    final d = dt.day.toString().padLeft(2, ' ');
    final hr = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m $d $hr:$min';
  }

  bool get isParentDir => isDir && name == '..';

  static FileExplorerItem parentDir(String parentPath) {
    return FileExplorerItem(
      name: '..',
      path: parentPath,
      isDir: true,
      size: 0,
      modified: '- -',
      isSelected: false,
    );
  }
}

class FileDragPayload {
  final PaneSide sourceSide;
  final ExplorerNodeTarget sourceTarget;
  final String sourceDirPath;
  final List<FileExplorerItem> items;

  const FileDragPayload({
    required this.sourceSide,
    required this.sourceTarget,
    required this.sourceDirPath,
    required this.items,
  });
}

enum PaneSide {
  left,
  right,
}

enum FileExplorerDensity {
  compact('Compact', 22.0, 11.5, 14.0),
  standard('Standard', 28.0, 13.0, 18.0),
  large('Large', 34.0, 15.0, 22.0);

  final String label;
  final double rowHeight;
  final double fontSize;
  final double iconSize;

  const FileExplorerDensity(this.label, this.rowHeight, this.fontSize, this.iconSize);
}

enum FileExplorerFontFamily {
  monospace('Monospace (Terminal)', 'monospace'),
  sansSerif('Sans-Serif (Modern)', null);

  final String label;
  final String? fontFamily;

  const FileExplorerFontFamily(this.label, this.fontFamily);
}

enum FileExplorerIconTheme {
  smart('Smart Extension Icons'),
  classic('Classic Folder & File');

  final String label;

  const FileExplorerIconTheme(this.label);
}

enum ExplorerInputMode {
  normal,
  search,
  newFile,
  newFolder,
  rename,
  confirmDelete,
  confirmCopy,
  confirmMove,
  confirmExit,
  mergeFileName,
  help,
  viewFile,
  selectNode,
}
