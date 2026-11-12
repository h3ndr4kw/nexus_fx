import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/known_hosts_service.dart';
import '../theme/app_theme.dart';

/// Asks whether to trust an SSH host key. Returns [HostKeyDecision.reject]
/// when dismissed.
///
/// First contact offers "Trust & connect" (remembered) or "Connect once".
/// A changed key is presented as a possible attack: Cancel is the default
/// action and replacing the stored key is a deliberate, separate choice.
Future<HostKeyDecision> showHostKeyDialog(
  BuildContext context,
  HostKeyPromptRequest request,
) async {
  final result = await showDialog<HostKeyDecision>(
    context: context,
    barrierDismissible: false,
    builder: (_) => HostKeyDialog(request: request),
  );
  return result ?? HostKeyDecision.reject;
}

class HostKeyDialog extends StatelessWidget {
  const HostKeyDialog({super.key, required this.request});

  final HostKeyPromptRequest request;

  bool get _changed => request.status == HostKeyStatus.changed;

  String get _target =>
      request.port == 22 ? request.host : '${request.host}:${request.port}';

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.activePalette;
    final tone = _changed ? p.errorColor : p.warningColor;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(HostKeyDecision.reject),
      },
      child: AlertDialog(
        backgroundColor: p.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: tone.withValues(alpha: 0.6), width: 1),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        title: Row(
          children: [
            Icon(
              _changed ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
              color: tone,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _changed ? 'Host key has changed' : 'Verify host identity',
                style: TextStyle(
                  color: p.titleColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: TextStyle(color: p.textColor, fontSize: 13, height: 1.45),
                  children: [
                    TextSpan(
                      text: _changed
                          ? 'The key presented by '
                          : 'This is the first connection to ',
                    ),
                    TextSpan(
                      text: _target,
                      style: TextStyle(
                        color: p.titleColor,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (request.via != null) TextSpan(text: ' (via ${request.via})'),
                    TextSpan(
                      text: _changed
                          ? ' does not match the one you trusted. The server may have been '
                              'reinstalled, or someone may be intercepting the connection. '
                              'Do not continue unless you know why it changed.'
                          : '. Before your password is sent, confirm this fingerprint '
                              'matches the server (ask its admin, or run '
                              'ssh-keygen -lf on its host key).',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_changed && request.previousFingerprint != null) ...[
                _FingerprintBox(
                  label: 'Previously trusted',
                  keyType: request.keyType,
                  fingerprint: request.previousFingerprint!,
                  muted: true,
                ),
                const SizedBox(height: 8),
              ],
              _FingerprintBox(
                label: _changed ? 'Presented now' : 'Fingerprint',
                keyType: request.keyType,
                fingerprint: request.fingerprint,
                accent: _changed ? p.errorColor : null,
              ),
            ],
          ),
        ),
        actions: _changed ? _changedActions(context, p) : _unknownActions(context, p),
      ),
    );
  }

  List<Widget> _unknownActions(BuildContext context, AppPalette p) => [
        TextButton(
          onPressed: () => Navigator.of(context).pop(HostKeyDecision.reject),
          style: TextButton.styleFrom(foregroundColor: p.textColor),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(HostKeyDecision.trustOnce),
          style: OutlinedButton.styleFrom(
            foregroundColor: p.titleColor,
            side: BorderSide(color: p.inputBorderColor),
          ),
          child: const Text('Connect once'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(HostKeyDecision.trustAlways),
          style: FilledButton.styleFrom(
            backgroundColor: p.primaryColor,
            foregroundColor: p.background,
          ),
          child: const Text('Trust & connect'),
        ),
      ];

  List<Widget> _changedActions(BuildContext context, AppPalette p) => [
        TextButton(
          onPressed: () => Navigator.of(context).pop(HostKeyDecision.trustAlways),
          style: TextButton.styleFrom(foregroundColor: p.errorColor),
          child: const Text('Replace key & connect'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(HostKeyDecision.reject),
          style: FilledButton.styleFrom(
            backgroundColor: p.primaryColor,
            foregroundColor: p.background,
          ),
          child: const Text('Cancel connection'),
        ),
      ];
}

class _FingerprintBox extends StatelessWidget {
  const _FingerprintBox({
    required this.label,
    required this.keyType,
    required this.fingerprint,
    this.muted = false,
    this.accent,
  });

  final String label;
  final String keyType;
  final String fingerprint;
  final bool muted;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.activePalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent?.withValues(alpha: 0.5) ?? p.inputBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · $keyType',
                  style: TextStyle(color: p.textColor, fontSize: 11),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  fingerprint,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: muted ? p.textColor : p.titleColor,
                    decoration: muted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy fingerprint',
            iconSize: 16,
            color: p.textColor,
            onPressed: () => Clipboard.setData(ClipboardData(text: fingerprint)),
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}
