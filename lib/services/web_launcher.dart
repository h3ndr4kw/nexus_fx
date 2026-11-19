import 'dart:io';

/// Outcome of [WebLauncher.openFirstReachable].
class WebOpenResult {
  /// The URL handed to the browser, or null if the browser could not start.
  final String? url;

  /// True when an earlier candidate was unreachable and a later one was used.
  final bool usedFallback;

  /// True when no candidate answered, so the first one was opened anyway.
  final bool noneReachable;

  const WebOpenResult({this.url, this.usedFallback = false, this.noneReachable = false});
}

/// Opens a URL in the system default browser.
///
/// Uses the OS handler directly instead of `cmd /c start`, so characters
/// like `&` in the URL are not interpreted by a shell.
class WebLauncher {
  static const Duration probeTimeout = Duration(seconds: 3);

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

  /// True when a TCP connection to the URL's host and port succeeds.
  static Future<bool> isReachable(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    try {
      final socket = await Socket.connect(uri.host, uri.port, timeout: probeTimeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the first of [urls] that accepts a TCP connection, mirroring the
  /// SSH primary -> fallback host switch. A single URL is opened without a
  /// probe. If none answers, the first one is opened anyway so the browser
  /// shows its own error.
  static Future<WebOpenResult> openFirstReachable(
    List<String> urls, {
    Future<bool> Function(String url) probe = isReachable,
    Future<bool> Function(String url) launch = open,
  }) async {
    if (urls.isEmpty) return const WebOpenResult();
    var target = urls.first;
    var usedFallback = false;
    var noneReachable = urls.length > 1;
    if (urls.length > 1) {
      for (var i = 0; i < urls.length; i++) {
        if (await probe(urls[i])) {
          target = urls[i];
          usedFallback = i > 0;
          noneReachable = false;
          break;
        }
      }
    }
    final ok = await launch(target);
    return WebOpenResult(
      url: ok ? target : null,
      usedFallback: usedFallback,
      noneReachable: noneReachable,
    );
  }
}
