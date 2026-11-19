import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/web_launcher.dart';

void main() {
  const primary = 'https://10.89.100.11';
  const fallback = 'https://10.89.200.11';

  Future<(WebOpenResult, List<String>, List<String>)> run(
    List<String> urls, {
    required Set<String> up,
    bool launchOk = true,
  }) async {
    final probed = <String>[];
    final launched = <String>[];
    final result = await WebLauncher.openFirstReachable(
      urls,
      probe: (u) async {
        probed.add(u);
        return up.contains(u);
      },
      launch: (u) async {
        launched.add(u);
        return launchOk;
      },
    );
    return (result, probed, launched);
  }

  test('opens the primary when it answers and skips the fallback probe', () async {
    final (result, probed, launched) = await run([primary, fallback], up: {primary, fallback});
    expect(launched, [primary]);
    expect(probed, [primary]);
    expect(result.usedFallback, isFalse);
    expect(result.noneReachable, isFalse);
  });

  test('switches to the fallback when the primary is down', () async {
    final (result, _, launched) = await run([primary, fallback], up: {fallback});
    expect(launched, [fallback]);
    expect(result.url, fallback);
    expect(result.usedFallback, isTrue);
  });

  test('opens the primary anyway when nothing answers', () async {
    final (result, _, launched) = await run([primary, fallback], up: {});
    expect(launched, [primary]);
    expect(result.noneReachable, isTrue);
  });

  test('a single URL is opened without probing', () async {
    final (result, probed, launched) = await run([primary], up: {});
    expect(probed, isEmpty);
    expect(launched, [primary]);
    expect(result.noneReachable, isFalse);
  });

  test('reports a browser launch failure with a null url', () async {
    final (result, _, _) = await run([primary], up: {}, launchOk: false);
    expect(result.url, isNull);
  });
}
