import 'dart:io';

/// Opens a URL in the system default browser.
///
/// Uses the OS handler directly instead of `cmd /c start`, so characters
/// like `&` in the URL are not interpreted by a shell.
class WebLauncher {
  static Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return false;
    }
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        result = await Process.run('open', [url]);
      } else {
        result = await Process.run('xdg-open', [url]);
      }
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
