import 'package:material_ui/material_ui.dart';

import '../models/file_explorer_models.dart';
import '../theme/app_theme.dart';

/// Picks the icon and its colour for a file explorer row from the file
/// type and the configured icon theme.
class FileExplorerIconHelper {
  static IconData getIconData(FileExplorerItem item, FileExplorerIconTheme iconTheme) {
    if (item.isDir) {
      if (item.name == '..') {
        return Icons.drive_folder_upload_rounded;
      }
      return Icons.folder_rounded;
    }

    if (iconTheme == FileExplorerIconTheme.classic) {
      return Icons.insert_drive_file_outlined;
    }

    final name = item.name.toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    final ext = dotIndex != -1 && dotIndex < name.length - 1 ? name.substring(dotIndex + 1) : '';

    switch (ext) {
      // Code & Scripts
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'html':
      case 'css':
      case 'c':
      case 'cpp':
      case 'h':
      case 'go':
      case 'rs':
      case 'java':
      case 'kt':
      case 'php':
      case 'rb':
      case 'sql':
        return Icons.code_rounded;
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'ps1':
      case 'bat':
      case 'cmd':
        return Icons.terminal_rounded;

      // Config & Data
      case 'yaml':
      case 'yml':
      case 'json':
      case 'xml':
      case 'toml':
      case 'ini':
      case 'conf':
      case 'cfg':
      case 'env':
      case 'properties':
        return Icons.tune_rounded;

      // Git & Lockfiles
      case 'gitignore':
      case 'gitattributes':
      case 'lock':
        return Icons.lock_outline;

      // Archives
      case 'zip':
      case 'tar':
      case 'gz':
      case 'tgz':
      case '7z':
      case 'rar':
      case 'bz2':
      case 'xz':
        return Icons.archive_outlined;

      // Images
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'ico':
      case 'webp':
      case 'bmp':
        return Icons.image_outlined;

      // Documents
      case 'txt':
      case 'md':
      case 'markdown':
      case 'doc':
      case 'docx':
      case 'pdf':
      case 'rtf':
        return Icons.description_outlined;

      // Logs
      case 'log':
      case 'out':
      case 'err':
        return Icons.article_outlined;

      // Network / Packet Captures
      case 'pcap':
      case 'pcapng':
      case 'cap':
        return Icons.network_check_rounded;

      // Binaries & Executables
      case 'exe':
      case 'dll':
      case 'so':
      case 'dylib':
      case 'bin':
      case 'msi':
      case 'apk':
        return Icons.settings_applications_outlined;

      // Certificates & Keys
      case 'pem':
      case 'crt':
      case 'cer':
      case 'key':
      case 'pub':
      case 'pfx':
      case 'p12':
        return Icons.key_rounded;

      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color getIconColor(FileExplorerItem item, FileExplorerIconTheme iconTheme, bool isSelected) {
    if (isSelected) {
      return AppTheme.adaptive(const Color(0xFF98C379));
    }

    if (item.isDir) {
      if (item.name == '..') {
        return AppTheme.adaptive(const Color(0xFF61AFEF));
      }
      return AppTheme.adaptive(const Color(0xFFE5C07B));
    }

    if (iconTheme == FileExplorerIconTheme.classic) {
      return AppTheme.adaptive(const Color(0xFFABB2BF));
    }

    final name = item.name.toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    final ext = dotIndex != -1 && dotIndex < name.length - 1 ? name.substring(dotIndex + 1) : '';

    switch (ext) {
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'html':
      case 'css':
      case 'c':
      case 'cpp':
      case 'h':
      case 'go':
      case 'rs':
      case 'java':
      case 'kt':
      case 'php':
      case 'rb':
      case 'sql':
        return AppTheme.adaptive(const Color(0xFF56B6C2));
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'ps1':
      case 'bat':
      case 'cmd':
        return AppTheme.adaptive(const Color(0xFF98C379));

      case 'yaml':
      case 'yml':
      case 'json':
      case 'xml':
      case 'toml':
      case 'ini':
      case 'conf':
      case 'cfg':
      case 'env':
      case 'properties':
        return AppTheme.adaptive(const Color(0xFFE5C07B));

      case 'gitignore':
      case 'gitattributes':
      case 'lock':
        return AppTheme.adaptive(const Color(0xFF828997));

      case 'zip':
      case 'tar':
      case 'gz':
      case 'tgz':
      case '7z':
      case 'rar':
      case 'bz2':
      case 'xz':
        return AppTheme.adaptive(const Color(0xFFD19A66));

      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'ico':
      case 'webp':
      case 'bmp':
        return AppTheme.adaptive(const Color(0xFFC678DD));

      case 'txt':
      case 'md':
      case 'markdown':
      case 'doc':
      case 'docx':
      case 'pdf':
      case 'rtf':
        return AppTheme.adaptive(const Color(0xFF61AFEF));

      case 'log':
      case 'out':
      case 'err':
        return AppTheme.adaptive(const Color(0xFFE06C75));

      case 'pcap':
      case 'pcapng':
      case 'cap':
        return AppTheme.adaptive(const Color(0xFF98C379));

      case 'exe':
      case 'dll':
      case 'so':
      case 'dylib':
      case 'bin':
      case 'msi':
      case 'apk':
        return AppTheme.adaptive(const Color(0xFF98C379));

      case 'pem':
      case 'crt':
      case 'cer':
      case 'key':
      case 'pub':
      case 'pfx':
      case 'p12':
        return AppTheme.adaptive(const Color(0xFFE5C07B));

      default:
        return AppTheme.adaptive(const Color(0xFFD8DEE9));
    }
  }
}
