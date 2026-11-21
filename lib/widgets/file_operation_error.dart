import 'package:material_ui/material_ui.dart';

import '../services/app_log.dart';
import '../theme/app_theme.dart';

/// Reports a file operation the user asked for and that failed: a message on
/// screen naming the [action] ("rename "a.nxnb"") and the reason, plus an
/// entry in the diagnostic log.
void reportFileOperationError(
  BuildContext context,
  String action,
  Object error,
  StackTrace stack,
) {
  AppLog.error('File operation: $action', error, stack);
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text('Could not $action: $error'),
      backgroundColor: AppTheme.statusError,
    ),
  );
}
