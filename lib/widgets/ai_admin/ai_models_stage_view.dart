import 'package:flutter/material.dart';

import '../../models/ai_model_config.dart';
import '../../models/api_key_config.dart';
import '../../services/ai_model_storage.dart';
import '../../services/api_key_storage.dart';
import 'ai_api_keys_stage_view.dart';

class AiModelsStageView extends StatefulWidget {
  const AiModelsStageView({
    super.key,
    this.storage = const AiModelStorage(),
    this.keyStorage = const ApiKeyStorage(),
    this.onSendToTest,
  });

  final AiModelStorage storage;
  final ApiKeyStorage keyStorage;
  final void Function(AiModelConfig model, bool isTts)? onSendToTest;

  @override
  State<AiModelsStageView> createState() => _AiModelsStageViewState();
}

class _AiModelsStageViewState extends State<AiModelsStageView> {
  // 0 = Chat Models, 1 = Voice / TTS Models
  int _selectedSubTab = 0;

  List<AiModelConfig> _chatModels = [];
  List<AiModelConfig> _ttsModels = [];
  List<ApiKeyConfig> _savedKeys = [];
  bool _isLoading = true;
  final Map<String, bool> _testingStatus = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant AiModelsStageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final chat = await widget.storage.getModels();
    final tts = await widget.storage.getTtsModels();
    final keys = await widget.keyStorage.getKeys();
    if (!mounted) return;
    setState(() {
      _chatModels = chat;
      _ttsModels = tts;
      _savedKeys = keys;
      _isLoading = false;
    });
  }

  Future<void> _handleSendToTest(AiModelConfig model, bool isTts) async {
    await widget.storage.sendModelToTesting(model.id, isTts: isTts);
    await _loadAll();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.science_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Model-ka "${model.displayName}" waxaa loo gudbiyay qaybta Test-ga!',
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0284C7),
        action: SnackBarAction(
          label: 'Gal Test-ga',
          textColor: Colors.white,
          onPressed: () => widget.onSendToTest?.call(model, isTts),
        ),
      ),
    );

    widget.onSendToTest?.call(model, isTts);
  }

  Future<void> _verifyQuickConnection(AiModelConfig model, bool isTts) async {
    setState(() => _testingStatus[model.id] = true);
    final res = isTts
        ? await widget.storage.verifyTtsModelConnection(model)
        : await widget.storage.verifyModelConnection(model);

    if (!mounted) return;
    setState(() => _testingStatus[model.id] = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              res.success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(res.message)),
          ],
        ),
        backgroundColor: res.success ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
      ),
    );
  }

  Future<void> _openModelFormDialog({
    AiModelConfig? existing,
    required bool isTts,
  }) async {
    // Crucial: Always fetch fresh keys directly from storage before opening the dialog!
    final freshKeys = await widget.keyStorage.getKeys();
    if (mounted) {
      setState(() {
        _savedKeys = freshKeys;
      });
    }

    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ModelFormDialog(
        storage: widget.storage,
        keyStorage: widget.keyStorage,
        savedKeys: freshKeys,
        existing: existing,
        isTts: isTts,
      ),
    );

    if (result == true) {
      await _loadAll();
    }
  }

  Future<void> _deleteModel(AiModelConfig model, bool isTts) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirtir Model-kan?'),
        content: Text('Ma hubtaa inaad tirtirto "${model.displayName}"?'),
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
      if (isTts) {
        await widget.storage.deleteTtsModel(model.id);
      } else {
        await widget.storage.deleteModel(model.id);
      }
      await _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isTts = _selectedSubTab == 1;
    final currentList = isTts ? _ttsModels : _chatModels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header & Controls
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
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              // Sub tabs toggle: Chat Models vs TTS Models
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSubTabButton(
                      index: 0,
                      label: 'Chat / LLM',
                      icon: Icons.chat_bubble_outline_rounded,
                      count: _chatModels.length,
                    ),
                    const SizedBox(width: 4),
                    _buildSubTabButton(
                      index: 1,
                      label: 'Codadka (TTS)',
                      icon: Icons.record_voice_over_rounded,
                      count: _ttsModels.length,
                    ),
                  ],
                ),
              ),

              // Add Model Button
              FilledButton.icon(
                onPressed: () => _openModelFormDialog(isTts: isTts),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  isTts ? 'Ku dar Model Cod ah (TTS)' : 'Ku dar Model Cusub',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0022FF),
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
        const SizedBox(height: 18),

        // Models list
        if (currentList.isEmpty)
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
                  isTts ? Icons.mic_off_rounded : Icons.smart_toy_outlined,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 12),
                Text(
                  isTts ? 'Weli ma jiraan TTS Models' : 'Weli ma jiraan Chat Models',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Guji "Ku dar Model Cusub" si aad ugu darto kaydka.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: currentList.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, idx) {
                final model = currentList[idx];
                final isVerifying = _testingStatus[model.id] == true;

                return _buildModelCard(model, isTts, isVerifying);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSubTabButton({
    required int index,
    required String label,
    required IconData icon,
    required int count,
  }) {
    final isSelected = _selectedSubTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedSubTab = index),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF0022FF) : Colors.grey.shade700,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF0022FF) : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF0022FF).withValues(alpha: 0.1)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? const Color(0xFF0022FF) : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard(AiModelConfig model, bool isTts, bool isVerifying) {
    final statusColor = model.isReady
        ? const Color(0xFF16A34A)
        : (model.isTesting ? const Color(0xFF0284C7) : const Color(0xFFEA580C));

    final statusLabel = model.isReady
        ? 'Diyaar ah (Ready)'
        : (model.isTesting ? 'Qaybta Tijaabada (Testing)' : 'Kaydka (Models)');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: model.isTesting
              ? const Color(0xFF0284C7).withValues(alpha: 0.4)
              : Colors.grey.shade200,
          width: model.isTesting ? 1.5 : 1.0,
        ),
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
          // Icon Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (isTts ? const Color(0xFF7C3AED) : const Color(0xFF0022FF))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                isTts ? Icons.record_voice_over_rounded : Icons.smart_toy_rounded,
                color: isTts ? const Color(0xFF7C3AED) : const Color(0xFF0022FF),
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      model.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        model.company,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: model.isFree
                            ? const Color(0xFF16A34A).withValues(alpha: 0.1)
                            : const Color(0xFFD97706).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        model.isFree ? 'Free Tier' : 'Paid Tier',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: model.isFree
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD97706),
                        ),
                      ),
                    ),
                    // Stage Tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '● $statusLabel',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Model ID: ',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                          ),
                          TextSpan(
                            text: model.modelId,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'API Key: ',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                          ),
                          TextSpan(
                            text: model.apiKeyId != null || model.apiKey.isNotEmpty
                                ? '••••••••'
                                : 'Furaha guud ee provider-ka',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Primary Stage Action: "U gudbi Test-ga"
          FilledButton.icon(
            onPressed: () => _handleSendToTest(model, isTts),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('U gudbi Test-ga'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
          ),
          const SizedBox(width: 8),

          // Quick ping test
          OutlinedButton.icon(
            onPressed: isVerifying ? null : () => _verifyQuickConnection(model, isTts),
            icon: isVerifying
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed_rounded, size: 15),
            label: Text(isVerifying ? 'Hubinta...' : 'Ping'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
          ),
          const SizedBox(width: 4),

          // Edit & Delete
          IconButton(
            tooltip: 'Wax ka beddel',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _openModelFormDialog(existing: model, isTts: isTts),
          ),
          IconButton(
            tooltip: 'Tirtir',
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
            onPressed: () => _deleteModel(model, isTts),
          ),
        ],
      ),
    );
  }
}

class _ModelFormDialog extends StatefulWidget {
  const _ModelFormDialog({
    required this.storage,
    required this.keyStorage,
    required this.savedKeys,
    this.existing,
    required this.isTts,
  });

  final AiModelStorage storage;
  final ApiKeyStorage keyStorage;
  final List<ApiKeyConfig> savedKeys;
  final AiModelConfig? existing;
  final bool isTts;

  @override
  State<_ModelFormDialog> createState() => _ModelFormDialogState();
}

class _ModelFormDialogState extends State<_ModelFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _modelIdController;
  late final TextEditingController _urlController;
  late final TextEditingController _customKeyController;

  String _company = 'Google';
  String? _selectedApiKeyId; // Selected from saved keys dropdown
  bool _useCustomKey = false;
  bool _isFree = true;
  bool _isActive = true;
  bool _isSaving = false;
  bool _isLoadingKeys = false;
  List<ApiKeyConfig> _currentKeys = [];

  final List<String> _companies = [
    'Google',
    'OpenAI',
    'Groq',
    'DeepSeek',
    'Anthropic',
    'Mistral AI',
    'Meta / Llama',
    'Custom Provider',
  ];

  @override
  void initState() {
    super.initState();
    _currentKeys = List<ApiKeyConfig>.from(widget.savedKeys);
    final ex = widget.existing;
    _nameController = TextEditingController(text: ex?.displayName ?? '');
    _modelIdController = TextEditingController(text: ex?.modelId ?? '');
    _urlController = TextEditingController(
      text: ex?.baseUrl ?? 'https://generativelanguage.googleapis.com',
    );
    _customKeyController = TextEditingController(text: ex?.apiKey ?? '');
    _company = ex?.company ?? 'Google';
    _isFree = ex?.isFree ?? true;
    _isActive = ex?.isActive ?? true;

    // Check if an existing key matches saved keys
    if (ex?.apiKeyId != null &&
        _currentKeys.any((k) => k.id == ex!.apiKeyId)) {
      _selectedApiKeyId = ex!.apiKeyId;
      _useCustomKey = false;
    } else if (ex?.apiKey != null && ex!.apiKey.isNotEmpty) {
      final match = _currentKeys.where((k) => k.apiKey == ex!.apiKey).firstOrNull;
      if (match != null) {
        _selectedApiKeyId = match.id;
        _useCustomKey = false;
      } else {
        _useCustomKey = true;
      }
    } else if (_currentKeys.isNotEmpty) {
      // Pick first matching provider key or first available
      final match = _currentKeys
          .where((k) => k.provider.toLowerCase() == _company.toLowerCase())
          .firstOrNull;
      _selectedApiKeyId = match?.id ?? _currentKeys.first.id;
      _useCustomKey = false;
      final picked = _currentKeys.firstWhere((k) => k.id == _selectedApiKeyId);
      if (picked.baseUrl.isNotEmpty && (ex == null || ex.baseUrl.isEmpty)) {
        _urlController.text = picked.baseUrl;
      }
    } else {
      _useCustomKey = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _modelIdController.dispose();
    _urlController.dispose();
    _customKeyController.dispose();
    super.dispose();
  }

  Future<void> _refreshKeys({String? autoSelectId}) async {
    setState(() => _isLoadingKeys = true);
    final fresh = await widget.keyStorage.getKeys();
    if (!mounted) return;
    setState(() {
      _currentKeys = fresh;
      _isLoadingKeys = false;
      if (autoSelectId != null && _currentKeys.any((k) => k.id == autoSelectId)) {
        _selectedApiKeyId = autoSelectId;
        _useCustomKey = false;
        final keyObj = _currentKeys.firstWhere((k) => k.id == autoSelectId);
        if (keyObj.baseUrl.isNotEmpty) {
          _urlController.text = keyObj.baseUrl;
        }
      } else if (_selectedApiKeyId != null && _currentKeys.any((k) => k.id == _selectedApiKeyId)) {
        // Keep selection
      } else if (_currentKeys.isNotEmpty) {
        final match = _currentKeys
            .where((k) => k.provider.toLowerCase() == _company.toLowerCase())
            .firstOrNull;
        _selectedApiKeyId = match?.id ?? _currentKeys.first.id;
        _useCustomKey = false;
      } else {
        _selectedApiKeyId = null;
        _useCustomKey = true;
      }
    });
  }

  Future<void> _quickAddNewApiKey() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ApiKeyFormDialog(storage: widget.keyStorage),
    );
    if (result == true) {
      final fresh = await widget.keyStorage.getKeys();
      final newestKey = fresh.isNotEmpty ? fresh.last : null;
      await _refreshKeys(autoSelectId: newestKey?.id);
    }
  }

  void _onApiKeyDropdownChanged(String? keyId) {
    if (keyId == null) return;
    setState(() {
      _selectedApiKeyId = keyId;
      _useCustomKey = false;
      final selectedKey = _currentKeys.where((k) => k.id == keyId).firstOrNull;
      if (selectedKey != null) {
        if (selectedKey.baseUrl.isNotEmpty) {
          _urlController.text = selectedKey.baseUrl;
        }
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    String resolvedApiKey = '';
    String? resolvedKeyId;

    if (_useCustomKey) {
      resolvedApiKey = _customKeyController.text.trim();
    } else if (_selectedApiKeyId != null) {
      final selectedKey = _currentKeys
          .where((k) => k.id == _selectedApiKeyId)
          .firstOrNull;
      if (selectedKey != null) {
        resolvedApiKey = selectedKey.apiKey;
        resolvedKeyId = selectedKey.id;
      }
    }

    final id = widget.existing?.id ??
        'model_${DateTime.now().millisecondsSinceEpoch}';

    final model = AiModelConfig(
      id: id,
      displayName: _nameController.text.trim(),
      modelId: _modelIdController.text.trim(),
      baseUrl: _urlController.text.trim(),
      apiKey: _useCustomKey ? resolvedApiKey : '',
      company: _company,
      isFree: _isFree,
      isVerified: widget.existing?.isVerified ?? false,
      isActive: _isActive,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      status: widget.existing?.status ?? 'models', // Starts in stage 1: models
      apiKeyId: resolvedKeyId,
      isTts: widget.isTts,
    );

    if (widget.isTts) {
      await widget.storage.saveTtsModel(model);
    } else {
      await widget.storage.saveModel(model);
    }

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
              color: (widget.isTts ? const Color(0xFF7C3AED) : const Color(0xFF0022FF))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.isTts ? Icons.record_voice_over_rounded : Icons.smart_toy_rounded,
              color: widget.isTts ? const Color(0xFF7C3AED) : const Color(0xFF0022FF),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isEdit ? 'Wax ka beddel Model' : 'Ku dar Model Cusub (Stage 1)',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Display Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Magaca Model-ka (Display Name)',
                    hintText: widget.isTts
                        ? 'Tusaale: Gemini 3.8 Flash TTS'
                        : 'Tusaale: Gemini 2.5 Flash',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Geli magaca model-ka' : null,
                ),
                const SizedBox(height: 14),

                // Model ID & Company Row
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _modelIdController,
                        decoration: InputDecoration(
                          labelText: 'Model ID (API Identifier)',
                          hintText: widget.isTts
                              ? 'gemini-3.8-flash-tts'
                              : 'gemini-2.5-flash',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Geli Model ID-ga'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _company,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Company / Bixiye',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        items: _companies
                            .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _company = val;
                              if (!_useCustomKey) {
                                final match = _currentKeys
                                    .where((k) => k.provider.toLowerCase() == val.toLowerCase())
                                    .firstOrNull;
                                if (match != null) {
                                  _selectedApiKeyId = match.id;
                                  if (match.baseUrl.isNotEmpty) {
                                    _urlController.text = match.baseUrl;
                                  }
                                }
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // API Key Dropdown Selector from Saved Keys
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.vpn_key_rounded,
                                size: 16,
                                color: Color(0xFF0022FF),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Furaha API-ga (Stage 5 API Keys)',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isLoadingKeys)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              else
                                IconButton(
                                  tooltip: 'Cusbooneysii liiska API Keys',
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _refreshKeys(),
                                ),
                              TextButton.icon(
                                onPressed: _quickAddNewApiKey,
                                icon: const Icon(Icons.add_rounded, size: 14),
                                label: const Text('Fure Cusub', style: TextStyle(fontSize: 11)),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                ),
                              ),
                              const SizedBox(width: 2),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _useCustomKey = !_useCustomKey;
                                    if (!_useCustomKey &&
                                        _currentKeys.isNotEmpty &&
                                        (_selectedApiKeyId == null ||
                                            !_currentKeys.any((k) => k.id == _selectedApiKeyId))) {
                                      _selectedApiKeyId = _currentKeys.first.id;
                                    }
                                  });
                                },
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                                child: Text(
                                  _useCustomKey ? 'Ka dooro API Keys' : 'Fure Custom ah',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (!_useCustomKey && _currentKeys.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: _currentKeys.any((k) => k.id == _selectedApiKeyId)
                              ? _selectedApiKeyId
                              : _currentKeys.first.id,
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          items: _currentKeys.map((key) {
                            return DropdownMenuItem(
                              value: key.id,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.vpn_key_rounded,
                                    size: 15,
                                    color: key.provider.toLowerCase().contains('google')
                                        ? const Color(0xFF1A73E8)
                                        : const Color(0xFF7C3AED),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${key.name} (${key.provider})',
                                      style: const TextStyle(fontSize: 12.5),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: _onApiKeyDropdownChanged,
                        ),
                      ] else if (!_useCustomKey && _currentKeys.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: Colors.amber.shade800),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Weli ma jiraan API Keys lagu keydiyay Stage 5. Riix "+ Fure Cusub" si aad ugu darto Google Gemini, Groq, OpenAI, ama isticmaal Custom Key.',
                                  style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _customKeyController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Furaha Custom API Key',
                            hintText: 'Geli furaha tooska ah...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _customKeyController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Furaha Custom API Key',
                            hintText: 'Geli furaha tooska ah...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Base URL
                TextFormField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://generativelanguage.googleapis.com',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),

                // Free vs Paid Tier switch
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        title: const Text('Bilaash (Free Tier)'),
                        subtitle: const Text('Ardayda oo dhan ayaa heli kara'),
                        value: _isFree,
                        onChanged: (v) => setState(() => _isFree = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: SwitchListTile(
                        title: const Text('Firfircoon (Active)'),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
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
            backgroundColor: const Color(0xFF0022FF),
          ),
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Keydinayaa...' : 'Keydi Model-ka'),
        ),
      ],
    );
  }
}
