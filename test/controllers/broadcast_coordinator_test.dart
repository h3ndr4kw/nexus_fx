import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/controllers/broadcast_coordinator.dart';
import 'package:nexus_fx/services/ssh_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BroadcastCoordinator Tests', () {
    late BroadcastCoordinator coordinator;

    setUp(() {
      coordinator = BroadcastCoordinator();
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('Initial state defaults to BroadcastTarget.all and empty history', () {
      expect(coordinator.target, BroadcastTarget.all);
      expect(coordinator.selectedConnectionIds, isEmpty);
      expect(coordinator.commandHistory, isEmpty);
      expect(coordinator.isParallelMode, isTrue);
      expect(coordinator.isSending, isFalse);
    });

    test('Setting broadcast target synchronizes connected selection', () {
      final left1 = SshConnection(id: 'l1', host: '10.0.0.1', port: 22, label: 'L1')
        ..setConnectedForTesting(true);
      final left2 = SshConnection(id: 'l2', host: '10.0.0.2', port: 22, label: 'L2'); // disconnected
      final right1 = SshConnection(id: 'r1', host: '10.0.0.3', port: 22, label: 'R1')
        ..setConnectedForTesting(true);

      coordinator.setTarget(
        BroadcastTarget.all,
        leftTabs: [left1, left2],
        rightTabs: [right1],
      );
      // Only connected connections are selected
      expect(coordinator.selectedConnectionIds, containsAll(['l1', 'r1']));
      expect(coordinator.selectedConnectionIds.contains('l2'), isFalse);

      coordinator.setTarget(
        BroadcastTarget.left,
        leftTabs: [left1, left2],
        rightTabs: [right1],
      );
      expect(coordinator.selectedConnectionIds, ['l1']);

      coordinator.setTarget(
        BroadcastTarget.right,
        leftTabs: [left1, left2],
        rightTabs: [right1],
      );
      expect(coordinator.selectedConnectionIds, ['r1']);
    });

    test('Command history records commands and navigates with Up/Down', () {
      coordinator.recordCommand('uptime');
      coordinator.recordCommand('df -h');
      coordinator.recordCommand('df -h'); // duplicate consecutive should not duplicate

      expect(coordinator.commandHistory, ['uptime', 'df -h']);

      // Navigate up from draft
      final up1 = coordinator.navigateHistoryUp('my current draft');
      expect(up1, 'df -h');
      expect(coordinator.commandDraft, 'my current draft');

      final up2 = coordinator.navigateHistoryUp('df -h');
      expect(up2, 'uptime');

      // Top of history reached
      final up3 = coordinator.navigateHistoryUp('uptime');
      expect(up3, 'uptime');

      // Navigate down back towards draft
      final down1 = coordinator.navigateHistoryDown();
      expect(down1, 'df -h');

      final down2 = coordinator.navigateHistoryDown();
      expect(down2, 'my current draft');
    });

    test('resolveTargetConnections filters correctly', () {
      final left1 = SshConnection(id: 'l1', host: '10.0.0.1', port: 22, label: 'L1')
        ..setConnectedForTesting(true);
      final right1 = SshConnection(id: 'r1', host: '10.0.0.2', port: 22, label: 'R1')
        ..setConnectedForTesting(true);

      // Single view (non-split) defaults to left tabs
      final singleViewTargets = coordinator.resolveTargetConnections(
        leftTabs: [left1],
        rightTabs: [right1],
        isSplitView: false,
      );
      expect(singleViewTargets.map((c) => c.id), ['l1']);

      // Split view with target all
      coordinator.setTarget(
        BroadcastTarget.all,
        leftTabs: [left1],
        rightTabs: [right1],
      );
      final splitTargets = coordinator.resolveTargetConnections(
        leftTabs: [left1],
        rightTabs: [right1],
        isSplitView: true,
      );
      expect(splitTargets.map((c) => c.id), containsAll(['l1', 'r1']));
    });

    test('executeBroadcast invokes sender for each target', () async {
      final left1 = SshConnection(id: 'l1', host: '10.0.0.1', port: 22, label: 'L1')
        ..setConnectedForTesting(true);

      final executed = <String>[];
      await coordinator.executeBroadcast(
        targetConnections: [left1],
        rawText: 'ls -la\npwd',
        customSender: (conn, cmd) async {
          executed.add('${conn.id}:$cmd');
        },
      );

      expect(executed, ['l1:ls -la', 'l1:pwd']);
      expect(coordinator.isSending, isFalse);
    });
  });
}
