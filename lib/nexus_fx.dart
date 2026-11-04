/// NexusFX Core Library & Plugin API
///
/// Import `package:nexus_fx/nexus_fx.dart` in downstream projects to launch
/// NexusFX with custom [NexusTool] plugins while receiving all upstream updates.
library;

export 'main.dart' show NexusFxApp, runNexusFxApp;

// Plugin & Extension System
export 'models/nexus_tool.dart';
export 'services/nexus_tool_registry.dart';

// Controllers
export 'controllers/broadcast_coordinator.dart';
export 'controllers/terminal_tab_controller.dart';

// Models
export 'models/cluster.dart';
export 'models/file_explorer_models.dart';
export 'models/network_manager_config.dart';
export 'models/playbook_models.dart';
export 'models/session_models.dart';
export 'models/ssh_tunnel_models.dart';

// Services
export 'services/crypto_vault_service.dart';
export 'services/file_explorer_service.dart';
export 'services/playbook_parser.dart';
export 'services/rust_sftp_bridge.dart';
export 'services/session_manager_service.dart';
export 'services/settings_service.dart';
export 'services/ssh_log_service.dart';
export 'services/ssh_service.dart';
export 'services/ssh_tunnel_manager.dart';
export 'services/window_state_service.dart';

// Screens
export 'screens/main_screen.dart';
export 'screens/nexus_screen.dart';
export 'screens/sessions_screen.dart';

// Theme
export 'theme/app_theme.dart';
export 'theme/terminal_theme_helper.dart';

// Reusable Widgets
export 'widgets/command_palette.dart';
export 'widgets/draggable_dialog.dart';
export 'widgets/fuzzy_searchable_dropdown.dart';
export 'widgets/radar_pulse_indicator.dart';
export 'widgets/sidebar_icon.dart';
export 'widgets/table_column_filter_header.dart';
