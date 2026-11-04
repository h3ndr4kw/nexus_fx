import 'package:flutter/material.dart';
import '../controllers/broadcast_coordinator.dart';
import '../controllers/terminal_tab_controller.dart';
import '../services/crypto_vault_service.dart';
import '../services/session_manager_service.dart';
import '../services/settings_service.dart';
import 'session_models.dart';

/// Context provided by NexusFX to custom [NexusTool] plugins, granting
/// direct access to core services, controllers, and navigation actions.
class NexusToolContext {
  final SessionManagerService sessionManager;
  final SettingsService settings;
  final CryptoVaultService cryptoVault;
  final TerminalTabController? tabController;
  final BroadcastCoordinator? broadcastCoordinator;

  /// Switches to the Nexus terminal workspace and connects the given [profile].
  final void Function(SessionProfile profile, {bool toRightPane}) connectSessionInTerminal;

  /// Switches to the Dual-Pane File Explorer and opens SFTP for [profile].
  final void Function(SessionProfile profile) openSessionInFileExplorer;

  /// Switches the active main view to the Nexus terminal workspace.
  final VoidCallback navigateToTerminal;

  /// Switches the active main view to the Sessions Manager view.
  final VoidCallback navigateToSessions;

  /// Switches the active main view to the File Explorer view.
  final VoidCallback navigateToFileExplorer;

  /// Switches the active main view to another registered custom tool by [toolId].
  final void Function(String toolId) navigateToTool;

  const NexusToolContext({
    required this.sessionManager,
    required this.settings,
    required this.cryptoVault,
    required this.tabController,
    required this.broadcastCoordinator,
    required this.connectSessionInTerminal,
    required this.openSessionInFileExplorer,
    required this.navigateToTerminal,
    required this.navigateToSessions,
    required this.navigateToFileExplorer,
    required this.navigateToTool,
  });
}

/// Represents a custom command contributed by a [NexusTool] to the Command Palette (`Ctrl+Shift+P`).
class NexusToolCommand {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final Color? badgeColor;
  final void Function(NexusToolContext context) onExecute;

  const NexusToolCommand({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onExecute,
    this.badge,
    this.badgeColor,
  });
}

/// Base contract for custom tools / plugins injected by downstream projects.
abstract class NexusTool {
  const NexusTool();

  /// Unique identifier for this tool (e.g., `'k8s_dashboard'`).
  String get id;

  /// Display title shown in the left navigation sidebar and Command Palette.
  String get title;

  /// Optional subtitle shown in the Command Palette when switching to this tool.
  String? get subtitle => null;

  /// Icon displayed in the left navigation sidebar and Command Palette.
  IconData get icon;

  /// Builds the main workspace view for this tool.
  ///
  /// The returned widget is hosted inside `MainScreen`'s `IndexedStack`,
  /// so its state is automatically preserved when switching between tabs.
  Widget buildView(BuildContext context, NexusToolContext toolContext);

  /// Optional list of commands contributed by this tool to the Command Palette.
  List<NexusToolCommand> buildCommands(NexusToolContext toolContext) => const [];
}
