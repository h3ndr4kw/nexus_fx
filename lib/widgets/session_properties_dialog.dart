import 'package:flutter/material.dart';
import '../models/session_models.dart';
import '../models/ssh_tunnel_models.dart';
import '../services/session_manager_service.dart';
import '../theme/app_theme.dart';
import 'fuzzy_searchable_dropdown.dart';

class SessionPropertiesResult {
  final SessionProfile savedSession;
  final bool connectNow;

  const SessionPropertiesResult({
    required this.savedSession,
    this.connectNow = false,
  });
}

enum _PropertyCategory {
  connection,
  authentication,
  tunneling,
  appearance,
  logging,
}

class _FolderDropdownItem {
  final String? id;
  final String label;

  const _FolderDropdownItem(this.id, this.label);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FolderDropdownItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class SessionPropertiesDialog extends StatefulWidget {
  final SessionProfile? initialSession;
  final String? parentFolderId;
  final SessionManagerService sessionManager;

  const SessionPropertiesDialog({
    super.key,
    this.initialSession,
    this.parentFolderId,
    required this.sessionManager,
  });

  static Future<SessionPropertiesResult?> show(
    BuildContext context, {
    SessionProfile? initialSession,
    String? parentFolderId,
    SessionManagerService? sessionManager,
  }) {
    final mgr = sessionManager ?? SessionManagerService.instance;
    return showDialog<SessionPropertiesResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SessionPropertiesDialog(
        initialSession: initialSession,
        parentFolderId: parentFolderId,
        sessionManager: mgr,
      ),
    );
  }

  @override
  State<SessionPropertiesDialog> createState() => _SessionPropertiesDialogState();
}

class _SessionPropertiesDialogState extends State<SessionPropertiesDialog> {
  _PropertyCategory _selectedCategory = _PropertyCategory.connection;
  Offset _dialogOffset = Offset.zero;

  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _fallbackHostController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _reconnectIntervalController;
  late final TextEditingController _reconnectLimitController;

  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _keyPathController;
  late final TextEditingController _keyPassphraseController;
  late final TextEditingController _loginScriptController;

  late final TextEditingController _customJumpHostController;
  late final TextEditingController _customJumpPortController;
  late final TextEditingController _customJumpFallbackController;
  late final TextEditingController _customJumpUsernameController;
  late final TextEditingController _customJumpPasswordController;

  late final TextEditingController _fontSizeController;
  late final TextEditingController _scrollbackController;

  SessionProtocol _protocol = SessionProtocol.ssh;
  SessionEnvironment _environment = SessionEnvironment.dev;
  AuthMethod _authMethod = AuthMethod.password;
  JumpHostMode _jumpHostMode = JumpHostMode.direct;
  String? _selectedJumpSessionId;
  String? _parentFolderId;
  TunnelMode _tunnelMode = TunnelMode.multiplexed;
  bool _autoReconnect = false;
  bool _enableLogging = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSession;
    _parentFolderId = s?.parentId ?? widget.parentFolderId;
    _protocol = s?.protocol ?? SessionProtocol.ssh;
    _environment = s?.environment ?? SessionEnvironment.dev;
    _authMethod = s?.authMethod ?? AuthMethod.password;
    _jumpHostMode = s?.jumpHostMode ?? JumpHostMode.direct;
    _selectedJumpSessionId = s?.jumpSessionId;
    _tunnelMode = s?.tunnelMode ?? TunnelMode.multiplexed;
    _autoReconnect = s?.autoReconnect ?? false;
    _enableLogging = s?.enableSessionLogging ?? true;

    _nameController = TextEditingController(text: s?.name ?? 'New Session');
    _hostController = TextEditingController(text: s?.host ?? '');
    _portController = TextEditingController(text: (s?.port ?? 22).toString());
    _fallbackHostController = TextEditingController(text: s?.fallbackHost ?? '');
    _descriptionController = TextEditingController(text: s?.description ?? '');
    _reconnectIntervalController = TextEditingController(text: (s?.reconnectIntervalSec ?? 30).toString());
    _reconnectLimitController = TextEditingController(text: (s?.reconnectLimitMin ?? 0).toString());

    _usernameController = TextEditingController(text: s?.username ?? '');
    _passwordController = TextEditingController(text: s?.password ?? '');
    _keyPathController = TextEditingController(text: s?.privateKeyPath ?? '');
    _keyPassphraseController = TextEditingController(text: s?.privateKeyPassphrase ?? '');
    _loginScriptController = TextEditingController(text: s?.loginScript ?? '');

    _customJumpHostController = TextEditingController(text: s?.customJumpHost ?? '');
    _customJumpPortController = TextEditingController(text: (s?.customJumpPort ?? 22).toString());
    _customJumpFallbackController = TextEditingController(text: s?.customJumpFallbackHost ?? '');
    _customJumpUsernameController = TextEditingController(text: s?.customJumpUsername ?? '');
    _customJumpPasswordController = TextEditingController(text: s?.customJumpPassword ?? '');

    _fontSizeController = TextEditingController(text: s?.customFontSize?.toString() ?? '');
    _scrollbackController = TextEditingController(text: (s?.scrollbackLines ?? 5000).toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _fallbackHostController.dispose();
    _descriptionController.dispose();
    _reconnectIntervalController.dispose();
    _reconnectLimitController.dispose();

    _usernameController.dispose();
    _passwordController.dispose();
    _keyPathController.dispose();
    _keyPassphraseController.dispose();
    _loginScriptController.dispose();

    _customJumpHostController.dispose();
    _customJumpPortController.dispose();
    _customJumpFallbackController.dispose();
    _customJumpUsernameController.dispose();
    _customJumpPasswordController.dispose();

    _fontSizeController.dispose();
    _scrollbackController.dispose();
    super.dispose();
  }

  bool _validateAndSave(bool connectNow) {
    setState(() => _errorMessage = null);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Session name cannot be empty.');
      return false;
    }

    if (_protocol == SessionProtocol.ssh) {
      final host = _hostController.text.trim();
      if (host.isEmpty) {
        setState(() => _errorMessage = 'Host cannot be empty for SSH session.');
        return false;
      }
      final port = int.tryParse(_portController.text.trim());
      if (port == null || port < 1 || port > 65535) {
        setState(() => _errorMessage = 'Port must be a number between 1 and 65535.');
        return false;
      }
    }

    // Check circular jump host if existingSession is selected
    if (_protocol == SessionProtocol.ssh && _jumpHostMode == JumpHostMode.existingSession) {
      if (_selectedJumpSessionId == null) {
        setState(() => _errorMessage = 'Please select a Jump Host session.');
        return false;
      }
      if (widget.initialSession != null && _selectedJumpSessionId == widget.initialSession!.id) {
        setState(() => _errorMessage = 'A session cannot use itself as a Jump Host.');
        return false;
      }
    }

    final id = widget.initialSession?.id ?? 'sess_${DateTime.now().microsecondsSinceEpoch}';
    final parentId = _parentFolderId;

    final session = SessionProfile(
      id: id,
      parentId: parentId,
      name: name,
      protocol: _protocol,
      environment: _environment,
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 22,
      fallbackHost: _fallbackHostController.text.trim().isEmpty ? null : _fallbackHostController.text.trim(),
      description: _descriptionController.text.trim(),
      autoReconnect: _autoReconnect,
      reconnectIntervalSec: int.tryParse(_reconnectIntervalController.text.trim()) ?? 30,
      reconnectLimitMin: int.tryParse(_reconnectLimitController.text.trim()) ?? 0,
      username: _usernameController.text.trim(),
      authMethod: _authMethod,
      password: _passwordController.text,
      privateKeyPath: _keyPathController.text.trim().isEmpty ? null : _keyPathController.text.trim(),
      privateKeyPassphrase: _keyPassphraseController.text.isEmpty ? null : _keyPassphraseController.text,
      loginScript: _loginScriptController.text,
      jumpHostMode: _jumpHostMode,
      jumpSessionId: _jumpHostMode == JumpHostMode.existingSession ? _selectedJumpSessionId : null,
      customJumpHost: _customJumpHostController.text.trim().isEmpty ? null : _customJumpHostController.text.trim(),
      customJumpPort: int.tryParse(_customJumpPortController.text.trim()) ?? 22,
      customJumpFallbackHost: _customJumpFallbackController.text.trim().isEmpty ? null : _customJumpFallbackController.text.trim(),
      customJumpUsername: _customJumpUsernameController.text.trim().isEmpty ? null : _customJumpUsernameController.text.trim(),
      customJumpPassword: _customJumpPasswordController.text.isEmpty ? null : _customJumpPasswordController.text,
      tunnelMode: _tunnelMode,
      customFontSize: double.tryParse(_fontSizeController.text.trim()),
      scrollbackLines: int.tryParse(_scrollbackController.text.trim()) ?? 5000,
      enableSessionLogging: _enableLogging,
      modifiedAt: DateTime.now(),
    );

    Navigator.of(context).pop(SessionPropertiesResult(savedSession: session, connectNow: connectNow));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Transform.translate(
        offset: _dialogOffset,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 840,
            maxHeight: 640,
            minWidth: 700,
            minHeight: 520,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderSubtle),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildDialogTitle(),
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: AppTheme.statusError.withValues(alpha: 0.15),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: AppTheme.statusError),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 12, color: AppTheme.statusError),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCategoryTree(),
                      const VerticalDivider(width: 1, thickness: 1, color: AppTheme.borderSubtle),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _buildCategoryContent(),
                        ),
                      ),
                      const VerticalDivider(width: 1, thickness: 1, color: AppTheme.borderSubtle),
                      _buildActionButtons(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogTitle() {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          setState(() {
            _dialogOffset += details.delta;
          });
        },
        onDoubleTap: () {
          setState(() {
            _dialogOffset = Offset.zero;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppTheme.bgSurfaceSecondary,
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              const Icon(Icons.settings_ethernet, size: 18, color: AppTheme.accentPrimary),
              const SizedBox(width: 8),
              Text(
                widget.initialSession == null ? 'Properties of New Session' : 'Properties of ${widget.initialSession!.name}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTree() {
    return Container(
      width: 190,
      color: AppTheme.bgSurfaceSecondary,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'Category:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
            ),
          ),
          _buildCategoryItem('Connection', _PropertyCategory.connection, Icons.cable, indent: 0),
          _buildCategoryItem('Authentication', _PropertyCategory.authentication, Icons.lock_outline, indent: 16),
          _buildCategoryItem('Tunneling (Jump Host)', _PropertyCategory.tunneling, Icons.alt_route, indent: 16),
          _buildCategoryItem('Appearance', _PropertyCategory.appearance, Icons.palette_outlined, indent: 0),
          _buildCategoryItem('Logging', _PropertyCategory.logging, Icons.description_outlined, indent: 0),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(String title, _PropertyCategory category, IconData icon, {double indent = 0}) {
    final isSelected = _selectedCategory == category;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = category),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: EdgeInsets.only(left: 8 + indent, right: 8, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentPrimary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isSelected ? Border.all(color: AppTheme.accentPrimary.withValues(alpha: 0.4)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppTheme.accentPrimary : AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryContent() {
    switch (_selectedCategory) {
      case _PropertyCategory.connection:
        return _buildConnectionTab();
      case _PropertyCategory.authentication:
        return _buildAuthenticationTab();
      case _PropertyCategory.tunneling:
        return _buildTunnelingTab();
      case _PropertyCategory.appearance:
        return _buildAppearanceTab();
      case _PropertyCategory.logging:
        return _buildLoggingTab();
    }
  }

  Widget _buildFolderDropdown() {
    final allFolders = widget.sessionManager.folders;
    final List<_FolderDropdownItem> items = [
      const _FolderDropdownItem(null, '/ (Root / All Sessions)'),
    ];
    for (final f in allFolders) {
      final crumbs = widget.sessionManager.getBreadcrumbPath(f.id);
      final path = crumbs.map((c) => c.name).join(' / ');
      items.add(_FolderDropdownItem(f.id, path));
    }
    final sublist = items.sublist(1)..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final sortedItems = [items.first, ...sublist];

    final selected = sortedItems.where((i) => i.id == _parentFolderId).firstOrNull ?? sortedItems.first;

    return Row(
      children: [
        const SizedBox(
          width: 110,
          child: Text('Folder:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ),
        Expanded(
          child: FuzzySearchableDropdown<_FolderDropdownItem>(
            items: sortedItems,
            selectedItem: selected,
            itemLabel: (item) => item.label,
            hintText: 'Select folder...',
            onChanged: (item) {
              setState(() {
                _parentFolderId = item?.id;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('General'),
          _buildTextField('Name:', _nameController),
          const SizedBox(height: 10),
          _buildFolderDropdown(),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 110,
                child: Text('Protocol:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              Expanded(
                child: FuzzySearchableDropdown<SessionProtocol>(
                  items: SessionProtocol.values,
                  selectedItem: _protocol,
                  itemLabel: (p) => p == SessionProtocol.ssh ? 'SSH' : 'LOCAL (System Shell)',
                  onChanged: (val) {
                    if (val != null) setState(() => _protocol = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 110,
                child: Text('Environment:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              Expanded(
                child: FuzzySearchableDropdown<SessionEnvironment>(
                  items: SessionEnvironment.values,
                  selectedItem: _environment,
                  itemLabel: (env) {
                    switch (env) {
                      case SessionEnvironment.dev:
                        return 'DEV (Development / Sandbox)';
                      case SessionEnvironment.staging:
                        return 'STAGING (Pre-production / QA)';
                      case SessionEnvironment.prod:
                        return 'PROD (Production / Live Critical)';
                    }
                  },
                  onChanged: (val) {
                    if (val != null) setState(() => _environment = val);
                  },
                ),
              ),
            ],
          ),
          if (_protocol == SessionProtocol.ssh) ...[
            const SizedBox(height: 10),
            _buildTextField('Host:', _hostController, hintText: '192.168.1.100 or domain'),
            const SizedBox(height: 10),
            _buildTextField('Port Number:', _portController, width: 100),
            const SizedBox(height: 10),
            _buildTextField('Fallback Host:', _fallbackHostController, hintText: 'Optional secondary IP/host'),
          ],
          const SizedBox(height: 10),
          _buildTextField('Description:', _descriptionController, maxLines: 2),
          const SizedBox(height: 16),
          _buildSectionHeader('Reconnect'),
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              title: const Text(
                'Reconnect automatically if connection is terminated unexpectedly',
                style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              ),
              value: _autoReconnect,
              onChanged: (val) => setState(() => _autoReconnect = val ?? false),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          if (_autoReconnect) ...[
            Row(
              children: [
                _buildTextField('Interval (sec):', _reconnectIntervalController, width: 80),
                const SizedBox(width: 24),
                _buildTextField('Limit (min, 0=unlimited):', _reconnectLimitController, width: 80),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuthenticationTab() {
    if (_protocol == SessionProtocol.local) {
      return const Center(
        child: Text(
          'Local shell inherits current user permissions. No authentication required.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Authentication'),
          _buildTextField('User Name:', _usernameController),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 110,
                child: Text('Method:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              Expanded(
                child: FuzzySearchableDropdown<AuthMethod>(
                  items: AuthMethod.values,
                  selectedItem: _authMethod,
                  itemLabel: (m) => m == AuthMethod.password ? 'Password' : 'Public Key / PEM File',
                  onChanged: (val) {
                    if (val != null) setState(() => _authMethod = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_authMethod == AuthMethod.password) ...[
            Row(
              children: [
                const SizedBox(
                  width: 110,
                  child: Text('Password:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ),
                Expanded(
                  child: TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 16),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        splashRadius: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            _buildTextField('Key Path:', _keyPathController, hintText: '/path/to/id_rsa or .pem'),
            const SizedBox(height: 10),
            _buildTextField('Passphrase:', _keyPassphraseController, obscureText: true),
          ],
          const SizedBox(height: 16),
          _buildSectionHeader('Login Scripts (Commands after connect)'),
          const SizedBox(height: 6),
          TextField(
            controller: _loginScriptController,
            maxLines: 4,
            style: const TextStyle(fontSize: 12, fontFamily: 'Consolas', color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g.\nsudo su -\nexport TERM=xterm-256color',
              hintStyle: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTunnelingTab() {
    if (_protocol == SessionProtocol.local) {
      return const Center(
        child: Text(
          'Tunneling / Jump Host is not applicable for Local Shell.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      );
    }

    final availableJumpSessions = widget.sessionManager.sessions
        .where((s) => s.protocol == SessionProtocol.ssh && (widget.initialSession == null || s.id != widget.initialSession!.id))
        .toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('SSH Tunneling / Jump Host'),
          Row(
            children: [
              const SizedBox(
                width: 130,
                child: Text('Connection Mode:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              Expanded(
                child: FuzzySearchableDropdown<JumpHostMode>(
                  items: JumpHostMode.values,
                  selectedItem: _jumpHostMode,
                  itemLabel: (m) {
                    switch (m) {
                      case JumpHostMode.direct:
                        return 'Direct Connection (No Jump Host)';
                      case JumpHostMode.existingSession:
                        return 'Via Existing SSH Session (Jump Host)';
                      case JumpHostMode.customJumpHost:
                        return 'Via Custom Jump Host (Manual Input)';
                    }
                  },
                  onChanged: (val) {
                    if (val != null) setState(() => _jumpHostMode = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_jumpHostMode == JumpHostMode.existingSession) ...[
            Row(
              children: [
                const SizedBox(
                  width: 130,
                  child: Text('Jump Session:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ),
                Expanded(
                  child: FuzzySearchableDropdown<SessionProfile>(
                    items: availableJumpSessions,
                    selectedItem: availableJumpSessions.where((s) => s.id == _selectedJumpSessionId).firstOrNull,
                    itemLabel: (s) => '${s.name} (${s.host}:${s.port})',
                    hintText: availableJumpSessions.isEmpty ? 'No other SSH sessions available' : 'Select Jump Host session...',
                    onChanged: (s) {
                      setState(() => _selectedJumpSessionId = s?.id);
                    },
                  ),
                ),
              ],
            ),
          ] else if (_jumpHostMode == JumpHostMode.customJumpHost) ...[
            _buildTextField('Jump Host:', _customJumpHostController, labelWidth: 130),
            const SizedBox(height: 10),
            _buildTextField('Jump Port:', _customJumpPortController, width: 80, labelWidth: 130),
            const SizedBox(height: 10),
            _buildTextField('Fallback Host:', _customJumpFallbackController, labelWidth: 130),
            const SizedBox(height: 10),
            _buildTextField('Username:', _customJumpUsernameController, labelWidth: 130),
            const SizedBox(height: 10),
            _buildTextField('Password:', _customJumpPasswordController, obscureText: true, labelWidth: 130),
          ],
          const SizedBox(height: 16),
          _buildSectionHeader('Multiplexing Mode'),
          Row(
            children: [
              const SizedBox(
                width: 130,
                child: Text('Tunnel Mode:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              Expanded(
                child: FuzzySearchableDropdown<TunnelMode>(
                  items: TunnelMode.values,
                  selectedItem: _tunnelMode,
                  itemLabel: (m) => m == TunnelMode.multiplexed ? 'Multiplexed (Shared Master Connection)' : 'Dedicated (New Socket)',
                  onChanged: (val) {
                    if (val != null) setState(() => _tunnelMode = val);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Terminal Font & Buffer'),
          _buildTextField('Custom Font Size:', _fontSizeController, hintText: 'Leave empty for default (14)'),
          const SizedBox(height: 10),
          _buildTextField('Scrollback Lines:', _scrollbackController, hintText: '5000'),
        ],
      ),
    );
  }

  Widget _buildLoggingTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Session Logging'),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            title: const Text(
              'Automatically log terminal session output to file upon connection',
              style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
            ),
            value: _enableLogging,
            onChanged: (val) => setState(() => _enableLogging = val ?? false),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentPrimary),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? hintText,
    double? width,
    double labelWidth = 110,
    int maxLines = 1,
    bool obscureText = false,
  }) {
    return Row(
      crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ),
        SizedBox(
          width: width,
          child: width != null
              ? TextField(
                  controller: controller,
                  maxLines: maxLines,
                  obscureText: obscureText,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: hintText,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                )
              : null,
        ),
        if (width == null)
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              obscureText: obscureText,
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: hintText,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Container(
      width: 115,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      color: AppTheme.bgSurfaceSecondary,
      child: Column(
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(double.infinity, 34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () => _validateAndSave(false),
            child: const Text('OK', style: TextStyle(fontSize: 12), maxLines: 1),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentPrimary,
              side: const BorderSide(color: AppTheme.accentPrimary),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(double.infinity, 34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () => _validateAndSave(true),
            child: const Text('Connect', style: TextStyle(fontSize: 12), maxLines: 1),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.borderSubtle),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(double.infinity, 34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(fontSize: 12), maxLines: 1),
          ),
        ],
      ),
    );
  }
}
