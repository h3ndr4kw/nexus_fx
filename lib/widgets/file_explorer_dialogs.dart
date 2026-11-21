import 'dart:isolate';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../models/file_explorer_models.dart';
import '../models/session_models.dart';
import '../services/file_explorer_service.dart';
import '../services/session_manager_service.dart';
import '../services/settings_service.dart';
import '../services/text_diff.dart';
import '../theme/app_theme.dart';
import 'palette_widgets.dart';

part 'file_explorer_dialog_shell.dart';
part 'file_explorer_help_dialog.dart';
part 'file_explorer_progress_dialog.dart';
part 'file_explorer_node_picker_dialog.dart';
part 'file_explorer_message_dialogs.dart';
part 'file_explorer_file_dialogs.dart';
part 'file_explorer_compare_dialog.dart';
part 'file_explorer_settings_dialog.dart';
