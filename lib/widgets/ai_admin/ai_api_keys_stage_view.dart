import 'package:flutter/material.dart';

import '../../models/api_key_config.dart';
import '../../services/api_key_storage.dart';

class AiApiKeysStageView extends StatefulWidget {
  const AiApiKeysStageView({
    super.key,
    this.storage = const ApiKeyStorage(),
    this.onKeysChanged,
  });

  final ApiKeyStorage storage;
  final VoidCallback? onKeysChanged;

  @override
  State<AiApiKeysStageView> createState() => _AiApiKeysStageViewState();
}

class _AiApiKeysStageViewState extends State<AiApiKeysStageView> {
  List<ApiKeyConfig> _keys = [];
  bool _isLoading = true;
  final Map<String, bool> _testingStatus = {};
  final Map<String, ({bool success, String message})> _testResults = {};

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() => _isLoading = true);
    late final List<ApiKeyConfig> list;
    try {
      list = await widget.storage.getKeys();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('API keys lama soo rari karin: $error')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _keys = list;
      _isLoading = false;
    });
  }

  Future<void> _testConnection(ApiKeyConfig keyConfig) async {
    setState(() => _testingStatus[keyConfig.id] = true);
    final result = await widget.storage.verifyApiKey(keyConfig);
    if (!mounted) return;
    setState(() {
      _testingStatus[keyConfig.id] = false;
      _testResults[keyConfig.id] = result;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              result.success
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(result.message)),
          ],
        ),
        backgroundColor: result.success
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626),
      ),
    );
  }

  Future<void> _openKeyFormDialog([ApiKeyConfig? existing]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          ApiKeyFormDialog(storage: widget.storage, existing: existing),
    );

    if (result == true) {
      await _loadKeys();
      widget.onKeysChanged?.call();
    }
  }

  Future<void> _deleteKey(ApiKeyConfig keyConfig) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirtir Furaha API-ga?'),
        content: Text(
          'Ma hubtaa inaad tirtirto furaha "${keyConfig.name}"? Moodellada ku xiran waxa laga yaabaa inay u baahdaan fure cusub.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Jooji'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tirtir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.storage.deleteKey(keyConfig.id);
      await _loadKeys();
      widget.onKeysChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top banner explaining API Keys stage
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  color: Color(0xFF7C3AED),
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kaydka Furayaasha API-ga (API Keys Vault)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Halkan ku kaydi dhammaan furayaasha API-yada (Google Gemini, Groq, OpenAI, iwm). Marka aad model cusub diyaarinayso, furaha waxaa toos looga dooranayaa liiskan (Dropdown).',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: () => _openKeyFormDialog(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ku dar API Key'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // List of API Keys
        if (_keys.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.key_off_rounded,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Weli ma jiraan API Keys la kaydiyay',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Guji badhanka "Ku dar API Key" si aad ugu darto furahaaga koowaad.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _keys.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, idx) {
                final key = _keys[idx];
                final isTesting = _testingStatus[key.id] == true;
                final testResult = _testResults[key.id];

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Provider icon avatar
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _getProviderColor(
                            key.provider,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(
                            _getProviderIcon(key.provider),
                            color: _getProviderColor(key.provider),
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  key.name,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getProviderColor(
                                      key.provider,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    key.provider,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _getProviderColor(key.provider),
                                    ),
                                  ),
                                ),
                                if (key.isActive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF16A34A,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Active',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 13,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _maskKey(key),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                if (key.baseUrl.isNotEmpty) ...[
                                  Icon(
                                    Icons.link_rounded,
                                    size: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      key.baseUrl,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (testResult != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    testResult.success
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    size: 13,
                                    color: testResult.success
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFDC2626),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      testResult.message,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: testResult.success
                                            ? const Color(0xFF16A34A)
                                            : const Color(0xFFDC2626),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Actions
                      OutlinedButton.icon(
                        onPressed: isTesting
                            ? null
                            : () => _testConnection(key),
                        icon: isTesting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.speed_rounded, size: 16),
                        label: Text(isTesting ? 'Hubinta...' : 'Tijaabi'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Wax ka beddel',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _openKeyFormDialog(key),
                      ),
                      IconButton(
                        tooltip: 'Tirtir',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.red,
                        ),
                        onPressed: () => _deleteKey(key),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _maskKey(ApiKeyConfig key) {
    if (!key.hasSecret && key.apiKey.isEmpty) return 'Fure wali lama gelin';
    return '••••••••••••';
  }

  Color _getProviderColor(String provider) {
    final p = provider.toLowerCase();
    if (p.contains('google')) return const Color(0xFF1A73E8);
    if (p.contains('openai')) return const Color(0xFF10A37F);
    if (p.contains('groq')) return const Color(0xFFF55036);
    if (p.contains('deepseek')) return const Color(0xFF0284C7);
    if (p.contains('anthropic')) return const Color(0xFFD97706);
    return const Color(0xFF7C3AED);
  }

  IconData _getProviderIcon(String provider) {
    final p = provider.toLowerCase();
    if (p.contains('google')) return Icons.g_mobiledata_rounded;
    if (p.contains('openai')) return Icons.bolt_rounded;
    if (p.contains('groq')) return Icons.flash_on_rounded;
    if (p.contains('deepseek')) return Icons.explore_rounded;
    if (p.contains('anthropic')) return Icons.psychology_rounded;
    return Icons.vpn_key_rounded;
  }
}

class ApiKeyFormDialog extends StatefulWidget {
  const ApiKeyFormDialog({super.key, required this.storage, this.existing});

  final ApiKeyStorage storage;
  final ApiKeyConfig? existing;

  @override
  State<ApiKeyFormDialog> createState() => _ApiKeyFormDialogState();
}

class _ApiKeyFormDialogState extends State<ApiKeyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _keyController;
  late final TextEditingController _urlController;
  late final TextEditingController _notesController;

  String _selectedProvider = 'Google';
  bool _obscureKey = true;
  bool _isActive = true;
  bool _isSaving = false;

  final List<String> _providers = [
    'Google',
    'OpenAI',
    'Groq',
    'DeepSeek',
    'Anthropic',
    'Other / Custom',
  ];

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nameController = TextEditingController(text: ex?.name ?? '');
    // Never prefill a saved API credential into the Flutter form.
    _keyController = TextEditingController();
    _urlController = TextEditingController(
      text: ex?.baseUrl ?? 'https://generativelanguage.googleapis.com',
    );
    _notesController = TextEditingController(text: ex?.notes ?? '');
    _selectedProvider = ex?.provider ?? 'Google';
    _isActive = ex?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keyController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onProviderChanged(String? provider) {
    if (provider == null) return;
    setState(() {
      _selectedProvider = provider;
      final p = provider.toLowerCase();
      if (p.contains('google')) {
        _urlController.text = 'https://generativelanguage.googleapis.com';
        if (_nameController.text.isEmpty ||
            _nameController.text.contains('Key')) {
          _nameController.text = 'Google Gemini API Key';
        }
      } else if (p.contains('groq')) {
        _urlController.text = 'https://api.groq.com/openai/v1';
        if (_nameController.text.isEmpty ||
            _nameController.text.contains('Key')) {
          _nameController.text = 'Groq Cloud API Key';
        }
      } else if (p.contains('openai')) {
        _urlController.text = 'https://api.openai.com/v1';
        if (_nameController.text.isEmpty ||
            _nameController.text.contains('Key')) {
          _nameController.text = 'OpenAI Official Key';
        }
      } else if (p.contains('deepseek')) {
        _urlController.text = 'https://api.deepseek.com';
        if (_nameController.text.isEmpty ||
            _nameController.text.contains('Key')) {
          _nameController.text = 'DeepSeek API Key';
        }
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final id =
        widget.existing?.id ?? 'key_${DateTime.now().millisecondsSinceEpoch}';

    final updated = ApiKeyConfig(
      id: id,
      name: _nameController.text.trim(),
      provider: _selectedProvider,
      apiKey:
          _keyController.text.trim().isEmpty &&
              widget.existing?.hasSecret == true
          ? widget.existing!.apiKey
          : _keyController.text.trim(),
      baseUrl: _urlController.text.trim(),
      isActive: _isActive,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      notes: _notesController.text.trim(),
      hasSecret:
          _keyController.text.trim().isNotEmpty ||
          (widget.existing?.hasSecret ?? false),
    );

    await widget.storage.saveKey(updated);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.vpn_key_rounded,
              color: Color(0xFF7C3AED),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isEdit ? 'Wax ka beddel API Key' : 'Ku dar API Key Cusub',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Provider Selector
                DropdownButtonFormField<String>(
                  initialValue: _selectedProvider,
                  decoration: InputDecoration(
                    labelText: 'Bixiyaha AI-ga (Provider)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: _providers
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: _onProviderChanged,
                ),
                const SizedBox(height: 14),

                // Name / Label
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Magaca Furaha (Friendly Name)',
                    hintText: 'Tusaale: Google Gemini Official Key',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Geli magaca furaha'
                      : null,
                ),
                const SizedBox(height: 14),

                // Secret API Key
                TextFormField(
                  controller: _keyController,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'Furaha Sirta ah (API Key)',
                    hintText: widget.existing?.hasSecret == true
                        ? 'Ka tag si aad u sii haysato furaha kaydsan.'
                        : 'Geli furahaaga halkan...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                  validator: (v) =>
                      v == null ||
                          (v.trim().isEmpty &&
                              widget.existing?.hasSecret != true)
                      ? 'Fadlan geli API Key-ga'
                      : null,
                ),
                const SizedBox(height: 14),

                // Base URL
                TextFormField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://generativelanguage.googleapis.com',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Active Switch
                SwitchListTile(
                  title: const Text('Furuhu waa firfircoon yahay (Active)'),
                  subtitle: const Text(
                    'Kani wuxuu u saamaxayaa moodellada inay doortaan',
                  ),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Jooji'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
          ),
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Keydinayaa...' : 'Keydi Furaha'),
        ),
      ],
    );
  }
}
