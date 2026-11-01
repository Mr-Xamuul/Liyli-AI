import 'package:flutter/material.dart';

import '../models/ai_model_config.dart';
import '../services/ai_model_storage.dart';
import '../services/gemini_tts_service.dart';

class AiModelManageView extends StatefulWidget {
  const AiModelManageView({
    super.key,
    this.storage = const AiModelStorage(),
    this.onModelSelectedForChat,
  });

  final AiModelStorage storage;
  final void Function(AiModelConfig model)? onModelSelectedForChat;

  @override
  State<AiModelManageView> createState() => AiModelManageViewState();
}

class AiModelManageViewState extends State<AiModelManageView> {
  List<AiModelConfig> _models = [];
  List<String> _companies = [];
  String? _selectedCategory; // null = Dhammaan
  String? _activeChatModelId;
  bool _isLoading = true;
  final Map<String, bool> _testingStatus = {};

  // Voice / TTS state
  int _selectedTab = 0; // 0 = Chat Models, 1 = Voice / TTS Models
  List<AiModelConfig> _ttsModels = [];
  String? _activeTtsModelId;
  final Map<String, bool> _ttsTestingStatus = {};
  final _ttsPlayer = GeminiTtsService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _ttsPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final models = await widget.storage.getModels();
    final companies = await widget.storage.getCompanies();
    final activeId = await widget.storage.getSelectedModelId();
    final ttsModels = await widget.storage.getTtsModels();
    final activeTtsId = await widget.storage.getSelectedTtsModelId();
    if (!mounted) return;
    setState(() {
      _models = models;
      _companies = companies;
      _activeChatModelId = activeId;
      _ttsModels = ttsModels;
      _activeTtsModelId = activeTtsId;
      _isLoading = false;
    });
  }

  /// Open dialog to create a new model (can be called from AppBar action `+`)
  void openCreateModelDialog() {
    if (_selectedTab == 1) {
      _showTtsModelFormDialog();
    } else {
      _showModelFormDialog();
    }
  }

  Future<void> _showModelFormDialog([AiModelConfig? existingModel]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AiModelFormDialog(
        storage: widget.storage,
        existingModel: existingModel,
      ),
    );

    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _testModelConnection(AiModelConfig model) async {
    setState(() => _testingStatus[model.id] = true);
    final res = await widget.storage.verifyModelConnection(model);
    if (!mounted) return;
    setState(() => _testingStatus[model.id] = false);

    if (res.success) {
      final updated = model.copyWith(isVerified: true);
      await widget.storage.saveModel(updated);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(res.message)),
            ],
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } else {
      final updated = model.copyWith(isVerified: false, isActive: false);
      await widget.storage.saveModel(updated);
      if (_activeChatModelId == model.id) {
        final all = await widget.storage.getModels();
        final working = all
            .where((m) => m.id != model.id && m.isVerified && m.isActive)
            .firstOrNull;
        await widget.storage.setSelectedModelId(working?.id ?? '');
        _activeChatModelId = working?.id;
      }
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(res.message)),
            ],
          ),
          backgroundColor: const Color(0xFFC62828),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _toggleActiveInChat(AiModelConfig model, bool active) async {
    if (active && !model.isVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lama fasixi karo model aan shaqeyneyn! Fadlan marka hore riix "Hubi Xiriirka".',
          ),
          backgroundColor: Color(0xFFC62828),
        ),
      );
      return;
    }
    final updated = model.copyWith(isActive: active);
    await widget.storage.saveModel(updated);
    await _loadData();
  }

  Future<void> _setAsChatModel(AiModelConfig model) async {
    if (!model.isVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lama fasixi karo model aan shaqeyneyn! Riix "Hubi Xiriirka" ka hor inta aanad u dooran Chat-ka.',
          ),
          backgroundColor: Color(0xFFC62828),
        ),
      );
      return;
    }
    await widget.storage.setSelectedModelId(model.id);
    if (!mounted) return;
    setState(() => _activeChatModelId = model.id);
    widget.onModelSelectedForChat?.call(model);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Waxaa loo xushay Chat-ka: ${model.displayName}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteModel(AiModelConfig model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ma hubtaa inaad tirtirto?'),
        content: Text(
          'Ma rabtaa inaad tirtirto model-ka "${model.displayName}"? Tallaabadan dib looma noqon karo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Maya'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            child: const Text('Haa, Tirtir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.storage.deleteModel(model.id);
      await _loadData();
    }
  }

  // ==================== TTS / Voice Models Methods ====================

  Future<void> _showTtsModelFormDialog([AiModelConfig? existingModel]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TtsModelFormDialog(
        storage: widget.storage,
        existingModel: existingModel,
      ),
    );

    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _testTtsModel(AiModelConfig model) async {
    setState(() => _ttsTestingStatus[model.id] = true);
    final res = await widget.storage.verifyTtsModelConnection(model);
    if (!mounted) return;
    setState(() => _ttsTestingStatus[model.id] = false);

    if (res.success) {
      final updated = model.copyWith(isVerified: true);
      await widget.storage.saveTtsModel(updated);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(res.message)),
            ],
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      // Play a quick test sound sample
      try {
        await _ttsPlayer.speak(
          id: 'tts_test_${model.id}',
          text: 'Codka ${model.displayName} wuu shaqeynayaa!',
          modelConfig: model,
        );
      } catch (_) {}
    } else {
      final updated = model.copyWith(isVerified: false, isActive: false);
      await widget.storage.saveTtsModel(updated);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(res.message)),
            ],
          ),
          backgroundColor: const Color(0xFFC62828),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _setAsActiveTtsModel(AiModelConfig model) async {
    await widget.storage.setSelectedTtsModelId(model.id);
    if (!mounted) return;
    setState(() => _activeTtsModelId = model.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Waxaa loo xushay Codka (TTS): ${model.displayName}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleTtsModelActive(AiModelConfig model, bool active) async {
    final updated = model.copyWith(isActive: active);
    await widget.storage.saveTtsModel(updated);
    await _loadData();
  }

  Future<void> _deleteTtsModel(AiModelConfig model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ma hubtaa inaad tirtirto?'),
        content: Text(
          'Ma rabtaa inaad tirtirto model-ka codka "${model.displayName}"? Tallaabadan dib looma noqon karo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Maya'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            child: const Text('Haa, Tirtir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.storage.deleteTtsModel(model.id);
      await _loadData();
    }
  }

  Widget _buildTtsTab(ThemeData theme) {
    if (_ttsModels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.record_voice_over_outlined,
                size: 64,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Wax model cod ah (TTS) lagama helin',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Riix badhanka "Ku dar Model Cod ah" si aad u diiwaangeliso model codka ah oo aad u geliso API Key-gaaga.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _showTtsModelFormDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Ku dar Model Cod ah'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: _ttsModels.length,
      itemBuilder: (context, index) {
        final model = _ttsModels[index];
        final isTesting = _ttsTestingStatus[model.id] == true;
        final isCurrentTts = _activeTtsModelId == model.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isCurrentTts
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isCurrentTts ? 1.8 : 1.0,
            ),
          ),
          color: isCurrentTts
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
              : theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Avatar, Name, Badges, Options
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.record_voice_over_rounded,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  model.displayName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCurrentTts) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Codka Daaran',
                                    style: TextStyle(
                                      color: theme.colorScheme.onPrimary,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  model.company,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'ID: ${model.modelId}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Wax ka beddel',
                      onPressed: () => _showTtsModelFormDialog(model),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: Colors.red.shade700,
                      ),
                      tooltip: 'Tirtir',
                      onPressed: () => _deleteTtsModel(model),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Badges
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: model.isVerified
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            model.isVerified
                                ? Icons.verified_rounded
                                : Icons.error_outline_rounded,
                            size: 13,
                            color: model.isVerified
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            model.isVerified ? 'Shaqeynaya' : 'Lama hubin',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: model.isVerified
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFC62828),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (model.apiKey.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Key: ${model.apiKey.length > 8 ? "${model.apiKey.substring(0, 4)}...${model.apiKey.substring(model.apiKey.length - 4)}" : "Diiwaangashan"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 10),
                // Action Buttons: Test Voice, Select for TTS, Switch
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isTesting
                            ? null
                            : () => _testTtsModel(model),
                        icon: isTesting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.volume_up_rounded, size: 16),
                        label: Text(
                          isTesting ? 'Waa la hubinayaa...' : 'Tijaabi Codka',
                        ),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!isCurrentTts)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _setAsActiveTtsModel(model),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: const Text('Dooro Codka'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF81C784)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check,
                              size: 16,
                              color: Color(0xFF2E7D32),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Codka Hadda',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 8),
                    Switch(
                      value: model.isActive,
                      onChanged: (val) => _toggleTtsModelActive(model, val),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredModels = _selectedCategory == null
        ? _models
        : _models
              .where(
                (m) =>
                    m.company.toLowerCase() == _selectedCategory!.toLowerCase(),
              )
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Banner / Info & Category Chips
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _selectedTab == 1
                          ? Icons.record_voice_over_rounded
                          : Icons.smart_toy_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedTab == 1
                              ? 'Maareynta Moodellada Codka (TTS)'
                              : 'Maareynta Moodellada AI',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _selectedTab == 1
                              ? 'Halkan ku dar, ku habee oo ku xaqiiji moodellada codka AI-ga iyo API Key-yada'
                              : 'Halkan ku dar, ku habee oo ku xaqiiji moodellada kala duwan ee AI-ga',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _selectedTab == 1
                        ? _showTtsModelFormDialog()
                        : _showModelFormDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      _selectedTab == 1 ? 'Ku dar Model Cod' : 'Ku dar Model',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Segmented Tab Toggle between Chat Models & Voice (TTS) Models
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => setState(() => _selectedTab = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0
                                ? theme.colorScheme.surface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: _selectedTab == 0
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 16,
                                color: _selectedTab == 0
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'Moodellada Chat-ka (${_models.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _selectedTab == 0
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: _selectedTab == 0
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => setState(() => _selectedTab = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1
                                ? theme.colorScheme.surface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: _selectedTab == 1
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.record_voice_over_rounded,
                                size: 16,
                                color: _selectedTab == 1
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'Moodellada Codka TTS (${_ttsModels.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _selectedTab == 1
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: _selectedTab == 1
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedTab == 0) ...[
                const SizedBox(height: 12),
                // Category filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        selected: _selectedCategory == null,
                        label: Text('Dhammaan (${_models.length})'),
                        onSelected: (_) =>
                            setState(() => _selectedCategory = null),
                        showCheckmark: false,
                      ),
                      const SizedBox(width: 8),
                      ..._companies.map((company) {
                        final count = _models
                            .where(
                              (m) =>
                                  m.company.toLowerCase() ==
                                  company.toLowerCase(),
                            )
                            .length;
                        final isSelected =
                            _selectedCategory?.toLowerCase() ==
                            company.toLowerCase();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: isSelected,
                            label: Text('$company ($count)'),
                            onSelected: (_) => setState(() {
                              _selectedCategory = isSelected ? null : company;
                            }),
                            showCheckmark: false,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // Body Content
        Expanded(
          child: _selectedTab == 1
              ? _buildTtsTab(theme)
              : filteredModels.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology_outlined,
                          size: 64,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Wax AI model ah lagama helin halkan',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Riix badhanka "Ku dar Model" si aad u diiwaangeliso model cusub.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _showModelFormDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Ku dar Model Cusub'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  itemCount: filteredModels.length,
                  itemBuilder: (context, index) {
                    final model = filteredModels[index];
                    final isTesting = _testingStatus[model.id] == true;
                    final isCurrentChat = _activeChatModelId == model.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isCurrentChat
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                          width: isCurrentChat ? 1.8 : 1.0,
                        ),
                      ),
                      color: isCurrentChat
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.15,
                            )
                          : theme.colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row: Avatar, Name, Badges, Options
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCompanyAvatar(model.company, theme),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              model.displayName,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isCurrentChat) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    theme.colorScheme.primary,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Chat Active',
                                                style: TextStyle(
                                                  color: theme
                                                      .colorScheme
                                                      .onPrimary,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              model.company,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'ID: ${model.modelId}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                                fontFamily: 'monospace',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert),
                                  tooltip: 'Fursado',
                                  onSelected: (val) {
                                    if (val == 'chat') _setAsChatModel(model);
                                    if (val == 'test')
                                      _testModelConnection(model);
                                    if (val == 'edit')
                                      _showModelFormDialog(model);
                                    if (val == 'delete') _deleteModel(model);
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'chat',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            size: 18,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('U dooro Chat-ka'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'test',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.network_check_rounded,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Hubi Xiriirka'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, size: 18),
                                          SizedBox(width: 8),
                                          Text('Wax ka beddel'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Color(0xFFC62828),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Tirtir',
                                            style: TextStyle(
                                              color: Color(0xFFC62828),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),
                            // URL preview
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.link_rounded,
                                    size: 15,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      model.baseUrl,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),
                            // Badges & Actions Row
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                // Free / Paid Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: model.isFree
                                        ? const Color(0xFFE8F5E9)
                                        : const Color(0xFFFFF8E1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: model.isFree
                                          ? const Color(0xFF81C784)
                                          : const Color(0xFFFFD54F),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        model.isFree
                                            ? Icons.money_off_rounded
                                            : Icons.workspace_premium_rounded,
                                        size: 14,
                                        color: model.isFree
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFFF57F17),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        model.isFree
                                            ? 'Bilaash (Free)'
                                            : 'Lacag (Paid)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: model.isFree
                                              ? const Color(0xFF1B5E20)
                                              : const Color(0xFFE65100),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Verification Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: model.isVerified
                                        ? const Color(0xFFE0F2F1)
                                        : const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: model.isVerified
                                          ? const Color(0xFF80CBC4)
                                          : const Color(0xFFEF9A9A),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        model.isVerified
                                            ? Icons.verified_rounded
                                            : Icons.warning_amber_rounded,
                                        size: 14,
                                        color: model.isVerified
                                            ? const Color(0xFF00796B)
                                            : const Color(0xFFC62828),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        model.isVerified
                                            ? 'Waa la hubiyay ✅'
                                            : 'Aan la hubin ⚠️',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: model.isVerified
                                              ? const Color(0xFF004D40)
                                              : const Color(0xFFB71C1C),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Active in Chat Toggle Switch
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Chat-ka:',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Switch(
                                      value: model.isActive && model.isVerified,
                                      onChanged: !model.isVerified
                                          ? null
                                          : (val) =>
                                                _toggleActiveInChat(model, val),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const Divider(height: 20),

                            // Footer Buttons: Hubi connection & U dooro chat-ka
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: isTesting
                                      ? null
                                      : () => _testModelConnection(model),
                                  icon: isTesting
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.network_check_rounded,
                                          size: 16,
                                        ),
                                  label: Text(
                                    isTesting ? 'Hubinta...' : 'Hubi Xiriirka',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (!isCurrentChat)
                                  FilledButton.tonalIcon(
                                    onPressed: !model.isVerified
                                        ? null
                                        : () => _setAsChatModel(model),
                                    icon: const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      model.isVerified
                                          ? 'Fasax Chat-ka'
                                          : 'Aan la hubin ⚠️',
                                    ),
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  )
                                else
                                  FilledButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Hadda Waa Active'),
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCompanyAvatar(String company, ThemeData theme) {
    final c = company.toLowerCase();
    Color bg = const Color(0xFF6750A4);
    String initials = 'AI';
    if (c.contains('google')) {
      bg = const Color(0xFF1A73E8);
      initials = 'G';
    } else if (c.contains('openai')) {
      bg = const Color(0xFF10A37F);
      initials = 'OA';
    } else if (c.contains('groq')) {
      bg = const Color(0xFFF55036);
      initials = 'GQ';
    } else if (c.contains('deepseek')) {
      bg = const Color(0xFF0066FF);
      initials = 'DS';
    } else if (c.contains('anthropic')) {
      bg = const Color(0xFFD97706);
      initials = 'AN';
    } else if (company.isNotEmpty) {
      initials = company
          .substring(0, company.length > 2 ? 2 : company.length)
          .toUpperCase();
    }

    return CircleAvatar(
      radius: 20,
      backgroundColor: bg,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Create / Edit Model Dialog with Live Connection Verification & Company registration
class _AiModelFormDialog extends StatefulWidget {
  const _AiModelFormDialog({required this.storage, this.existingModel});

  final AiModelStorage storage;
  final AiModelConfig? existingModel;

  @override
  State<_AiModelFormDialog> createState() => _AiModelFormDialogState();
}

class _AiModelFormDialogState extends State<_AiModelFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _displayNameController;
  late TextEditingController _modelIdController;
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _newCompanyController;

  String _selectedCompany = 'Google';
  bool _isFree = true;
  bool _isApiKeyVisible = false;
  bool _isAddingNewCompany = false;

  bool _isTesting = false;
  bool? _testSucceeded;
  String? _testFeedbackMessage;
  List<String> _companies = [];

  @override
  void initState() {
    super.initState();
    final m = widget.existingModel;
    _displayNameController = TextEditingController(text: m?.displayName ?? '');
    _modelIdController = TextEditingController(text: m?.modelId ?? '');
    _baseUrlController = TextEditingController(
      text: m?.baseUrl ?? AiModelStorage.suggestBaseUrl('Google'),
    );
    _apiKeyController = TextEditingController(text: m?.apiKey ?? '');
    _newCompanyController = TextEditingController();

    _selectedCompany = m?.company ?? 'Google';
    _isFree = m?.isFree ?? true;
    _testSucceeded = m?.isVerified;

    _modelIdController.addListener(_onParamChanged);
    _baseUrlController.addListener(_onParamChanged);
    _apiKeyController.addListener(_onParamChanged);

    _loadCompanies();
  }

  void _onParamChanged() {
    if (_testSucceeded != null || _testFeedbackMessage != null) {
      if (mounted) {
        setState(() {
          _testSucceeded = null;
          _testFeedbackMessage = null;
        });
      }
    }
  }

  Future<void> _loadCompanies() async {
    final list = await widget.storage.getCompanies();
    if (!mounted) return;
    setState(() {
      _companies = list;
      if (!_companies.contains(_selectedCompany)) {
        _companies.insert(0, _selectedCompany);
      }
    });
  }

  @override
  void dispose() {
    _modelIdController.removeListener(_onParamChanged);
    _baseUrlController.removeListener(_onParamChanged);
    _apiKeyController.removeListener(_onParamChanged);
    _displayNameController.dispose();
    _modelIdController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _newCompanyController.dispose();
    super.dispose();
  }

  void _onCompanyChanged(String? val) {
    if (val == null) return;
    if (val == '__NEW__') {
      setState(() {
        _isAddingNewCompany = true;
      });
      return;
    }

    setState(() {
      _selectedCompany = val;
      _isAddingNewCompany = false;
      // Auto-suggest URL if not manually modified
      _baseUrlController.text = AiModelStorage.suggestBaseUrl(val);
      _testSucceeded = null;
      _testFeedbackMessage = null;
    });
  }

  Future<void> _registerNewCompany() async {
    final newName = _newCompanyController.text.trim();
    if (newName.isEmpty) return;

    await widget.storage.addCompany(newName);
    if (!mounted) return;
    setState(() {
      if (!_companies.contains(newName)) {
        _companies.add(newName);
      }
      _selectedCompany = newName;
      _isAddingNewCompany = false;
      _baseUrlController.text = AiModelStorage.suggestBaseUrl(newName);
      _newCompanyController.clear();
    });
  }

  AiModelConfig _buildCurrentConfig() {
    final verified = _testSucceeded == true;
    return AiModelConfig(
      id:
          widget.existingModel?.id ??
          'model_${DateTime.now().millisecondsSinceEpoch}',
      displayName: _displayNameController.text.trim(),
      modelId: _modelIdController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      company: _selectedCompany,
      isFree: _isFree,
      isVerified: verified,
      isActive: verified,
      createdAt: widget.existingModel?.createdAt ?? DateTime.now(),
    );
  }

  Future<void> _runConnectionVerification() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testSucceeded = null;
      _testFeedbackMessage = null;
    });

    final tempConfig = _buildCurrentConfig();
    final res = await widget.storage.verifyModelConnection(tempConfig);

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testSucceeded = res.success;
      _testFeedbackMessage = res.message;
    });
  }

  Future<void> _submitSave() async {
    if (!_formKey.currentState!.validate()) return;

    if (_testSucceeded != true) {
      await _runConnectionVerification();
      if (_testSucceeded != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _testFeedbackMessage != null && _testFeedbackMessage!.isNotEmpty
                  ? 'Model-ku ma shaqeynayo: $_testFeedbackMessage. Lama fasixi karo model aan shaqeyneyn.'
                  : 'Fadlan marka hore hubi xiriirka model-ka ka hor inta aan la fasixin.',
            ),
            backgroundColor: const Color(0xFFC62828),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    final config = _buildCurrentConfig();
    await widget.storage.saveModel(config);

    // If verified, set as active model
    await widget.storage.setSelectedModelId(config.id);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingModel != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isEditing
                            ? Icons.edit_note_rounded
                            : Icons.add_circle_outline_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing
                                ? 'Wax ka beddel AI Model'
                                : 'Diiwaangeli AI Model Cusub',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Geli xogta model-ka, hubi xiriirka kadibna u fasax chat-ka',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Form Scrollable Body
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Shirkadda (Company / Provider Category)
                        Text(
                          '1. Shirkadda soo saartay AI-ga (Provider / Category):',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (!_isAddingNewCompany) ...[
                          DropdownButtonFormField<String>(
                            initialValue: _companies.contains(_selectedCompany)
                                ? _selectedCompany
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                Icons.business_rounded,
                                size: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            items: [
                              ..._companies.map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              ),
                              const DropdownMenuItem(
                                value: '__NEW__',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.add,
                                      size: 18,
                                      color: Colors.blue,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      '+ Ku dar shirkad cusub...',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: _onCompanyChanged,
                          ),
                        ] else ...[
                          // Inline adding of custom company
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _newCompanyController,
                                  decoration: InputDecoration(
                                    labelText: 'Magaca Shirkadda Cusub',
                                    hintText:
                                        'tusaale: xAI, Perplexity, Together AI...',
                                    prefixIcon: const Icon(
                                      Icons.add_business_rounded,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _registerNewCompany,
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('Diiwaan geli'),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.cancel_outlined),
                                tooltip: 'Ka noqo',
                                onPressed: () =>
                                    setState(() => _isAddingNewCompany = false),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 16),

                        // 2. Magaca Model-ka (Display Name in Chat)
                        Text(
                          '2. Magaca soo muuqanaya marka la joogo Chat-ka:',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _displayNameController,
                          decoration: InputDecoration(
                            hintText:
                                'tusaale: Gemini 2.5 Flash, GPT-4o Mini, Leyli Pro...',
                            prefixIcon: const Icon(
                              Icons.badge_outlined,
                              size: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Fadlan geli magaca soo muuqanaya ee model-ka';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // 3. Aqoonsiga Model-ka (Model ID)
                        Text(
                          '3. Aqoonsiga Model-ka (Model ID):',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _modelIdController,
                          decoration: InputDecoration(
                            hintText:
                                'tusaale: gemini-2.5-flash, gpt-4o-mini, llama-3.3-70b-versatile',
                            prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Fadlan geli Model ID-ga saxda ah';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // 4. URL / Base Endpoint
                        Text(
                          '4. URL / Endpoint-ka Adeegga API-ga:',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _baseUrlController,
                          decoration: InputDecoration(
                            hintText: 'tusaale: https://api.openai.com/v1',
                            prefixIcon: const Icon(
                              Icons.link_rounded,
                              size: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Fadlan geli URL-ka saxda ah';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // 5. API Key
                        Text(
                          '5. API Key-ga (Furaha Helitaanka):',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _apiKeyController,
                          obscureText: !_isApiKeyVisible,
                          decoration: InputDecoration(
                            hintText: 'Geli API Key-gaaga halkan...',
                            prefixIcon: const Icon(
                              Icons.vpn_key_outlined,
                              size: 20,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isApiKeyVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _isApiKeyVisible = !_isApiKeyVisible,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 6. Model Type (Free vs Paid)
                        Text(
                          '6. Nooca Model-ka (Qiimaha):',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _isFree = true),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isFree
                                        ? const Color(0xFFE8F5E9)
                                        : theme
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _isFree
                                          ? const Color(0xFF2E7D32)
                                          : Colors.transparent,
                                      width: 1.6,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 18,
                                        color: _isFree
                                            ? const Color(0xFF2E7D32)
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Bilaash (Free)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _isFree
                                                ? const Color(0xFF1B5E20)
                                                : theme.colorScheme.onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _isFree = false),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !_isFree
                                        ? const Color(0xFFFFF8E1)
                                        : theme
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: !_isFree
                                          ? const Color(0xFFF57F17)
                                          : Colors.transparent,
                                      width: 1.6,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.workspace_premium_rounded,
                                        size: 18,
                                        color: !_isFree
                                            ? const Color(0xFFF57F17)
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Lacag (Paid)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: !_isFree
                                                ? const Color(0xFFE65100)
                                                : theme.colorScheme.onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // 7. Qeybta Hubinta (Verification Section)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.verified_user_outlined,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Hubinta Xiriirka Model-ka',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Guji badhanka hoose si loo xaqiijiyo in API key-ga iyo URL-ka ay si sax ah u shaqeynayaan ka hor inta aan loo fasixin Chat-ka.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _isTesting
                                    ? null
                                    : _runConnectionVerification,
                                icon: _isTesting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.network_check_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  _isTesting
                                      ? 'Hubinta ayaa socota...'
                                      : 'Hubi Xiriirka Model-ka',
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),

                              // Feedback banner
                              if (_testFeedbackMessage != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _testSucceeded == true
                                        ? const Color(0xFFE8F5E9)
                                        : const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _testSucceeded == true
                                          ? const Color(0xFF81C784)
                                          : const Color(0xFFEF9A9A),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _testSucceeded == true
                                            ? Icons.check_circle_rounded
                                            : Icons.error_rounded,
                                        size: 18,
                                        color: _testSucceeded == true
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFFC62828),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _testFeedbackMessage!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: _testSucceeded == true
                                                ? const Color(0xFF1B5E20)
                                                : const Color(0xFFB71C1C),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Dialog Action Buttons: Cancel vs Save & Enable for Chat
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Ka noqo'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _isTesting ? null : _submitSave,
                      icon: Icon(
                        _testSucceeded == true
                            ? Icons.check_circle_outline
                            : Icons.network_check_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _testSucceeded == true
                            ? 'Keydi & Fasax Chat-ka'
                            : 'Hubi & Fasax Chat-ka',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: _testSucceeded == true
                            ? const Color(0xFF2E7D32)
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Create / Edit TTS Voice Model Dialog with Live Voice Verification
class _TtsModelFormDialog extends StatefulWidget {
  const _TtsModelFormDialog({required this.storage, this.existingModel});

  final AiModelStorage storage;
  final AiModelConfig? existingModel;

  @override
  State<_TtsModelFormDialog> createState() => _TtsModelFormDialogState();
}

class _TtsModelFormDialogState extends State<_TtsModelFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _displayNameController;
  late TextEditingController _modelIdController;
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _companyController;

  bool _isApiKeyVisible = false;
  bool _isTesting = false;
  bool? _testSucceeded;
  String? _testFeedbackMessage;

  static const List<String> _suggestedTtsModels = [
    'gemini-3.8-flash-tts',
    'gemini-3.8-flash-lite-tts',
    'gemini-3.1-flash-tts-preview',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
  ];

  @override
  void initState() {
    super.initState();
    final m = widget.existingModel;
    _displayNameController = TextEditingController(
      text: m?.displayName ?? 'Gemini 3.8 Flash TTS',
    );
    _modelIdController = TextEditingController(
      text: m?.modelId ?? 'gemini-3.8-flash-tts',
    );
    _baseUrlController = TextEditingController(
      text: m?.baseUrl ?? 'https://generativelanguage.googleapis.com',
    );
    _apiKeyController = TextEditingController(text: m?.apiKey ?? '');
    _companyController = TextEditingController(text: m?.company ?? 'Google');
    _testSucceeded = m?.isVerified;

    _modelIdController.addListener(_onParamChanged);
    _apiKeyController.addListener(_onParamChanged);
  }

  void _onParamChanged() {
    if (_testSucceeded != null || _testFeedbackMessage != null) {
      if (mounted) {
        setState(() {
          _testSucceeded = null;
          _testFeedbackMessage = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _modelIdController.removeListener(_onParamChanged);
    _apiKeyController.removeListener(_onParamChanged);
    _displayNameController.dispose();
    _modelIdController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _runTtsVerification() async {
    final modelId = _modelIdController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (modelId.isEmpty) {
      setState(() {
        _testSucceeded = false;
        _testFeedbackMessage =
            'Fadlan geli Model ID-ga codka ka hor inta aan la hubin.';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testFeedbackMessage = null;
    });

    final tempConfig = AiModelConfig(
      id:
          widget.existingModel?.id ??
          'temp_tts_${DateTime.now().millisecondsSinceEpoch}',
      displayName: _displayNameController.text.trim().isEmpty
          ? modelId
          : _displayNameController.text.trim(),
      modelId: modelId,
      baseUrl: _baseUrlController.text.trim().isEmpty
          ? 'https://generativelanguage.googleapis.com'
          : _baseUrlController.text.trim(),
      apiKey: apiKey,
      company: _companyController.text.trim().isEmpty
          ? 'Google'
          : _companyController.text.trim(),
      createdAt: widget.existingModel?.createdAt ?? DateTime.now(),
    );

    final res = await widget.storage.verifyTtsModelConnection(tempConfig);
    if (!mounted) return;

    setState(() {
      _isTesting = false;
      _testSucceeded = res.success;
      _testFeedbackMessage = res.message;
    });
  }

  Future<void> _submitSave() async {
    if (!_formKey.currentState!.validate()) return;

    final modelId = _modelIdController.text.trim();
    final displayName = _displayNameController.text.trim().isEmpty
        ? modelId
        : _displayNameController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim().isEmpty
        ? 'https://generativelanguage.googleapis.com'
        : _baseUrlController.text.trim();
    final company = _companyController.text.trim().isEmpty
        ? 'Google'
        : _companyController.text.trim();

    if (_testSucceeded != true) {
      await _runTtsVerification();
      if (_testSucceeded != true) {
        return;
      }
    }

    final newModel = AiModelConfig(
      id:
          widget.existingModel?.id ??
          'tts_${DateTime.now().millisecondsSinceEpoch}',
      displayName: displayName,
      modelId: modelId,
      baseUrl: baseUrl,
      apiKey: apiKey,
      company: company,
      isFree: true,
      isVerified: _testSucceeded == true,
      isActive: true,
      createdAt: widget.existingModel?.createdAt ?? DateTime.now(),
    );

    await widget.storage.saveTtsModel(newModel);

    final currentSelected = await widget.storage.getSelectedTtsModelId();
    if (currentSelected == null ||
        currentSelected.isEmpty ||
        widget.existingModel == null) {
      await widget.storage.setSelectedTtsModelId(newModel.id);
    }

    if (mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Model-ka codka "$displayName" si guul leh ayaa loo keydiyay!',
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingModel != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Dialog Title & Close
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.record_voice_over_rounded,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing
                                ? 'Wax ka beddel Model-ka Codka (TTS)'
                                : 'Ku dar Model Cusub oo Codka ah',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Geli xogta model-ka codka iyo API Key-gaaga',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Form Scrollable Body
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Display Name
                        Text(
                          'Magaca Muuqda (Display Name)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _displayNameController,
                          decoration: InputDecoration(
                            hintText: 'Tusaale: Gemini 3.8 Flash TTS',
                            prefixIcon: const Icon(
                              Icons.badge_outlined,
                              size: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Fadlan geli magaca model-ka'
                              : null,
                        ),
                        const SizedBox(height: 14),

                        // Model ID
                        Text(
                          'Model ID (Magaca Rasmiga ah ee Codka)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _modelIdController,
                          decoration: InputDecoration(
                            hintText: 'Tusaale: gemini-3.8-flash-tts',
                            prefixIcon: const Icon(
                              Icons.tune_rounded,
                              size: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Fadlan geli Model ID-ga codka'
                              : null,
                        ),
                        const SizedBox(height: 6),
                        // Quick Suggestions for TTS models
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _suggestedTtsModels.map((suggested) {
                            final isSelected =
                                _modelIdController.text.trim() == suggested;
                            return ActionChip(
                              label: Text(
                                suggested,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : null,
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  _modelIdController.text = suggested;
                                  if (_displayNameController.text.isEmpty ||
                                      _suggestedTtsModels.contains(
                                        _displayNameController.text
                                            .toLowerCase()
                                            .replaceAll(' ', '-'),
                                      )) {
                                    _displayNameController.text = suggested
                                        .replaceAll('-', ' ')
                                        .toUpperCase();
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        // Provider / Company
                        Text(
                          'Shirkadda / Bixiyaha (Company)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _companyController,
                          decoration: InputDecoration(
                            hintText: 'Google',
                            prefixIcon: const Icon(
                              Icons.business_outlined,
                              size: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // API Key
                        Text(
                          'API Key-ga Codka (Google Gemini API Key)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _apiKeyController,
                          obscureText: !_isApiKeyVisible,
                          decoration: InputDecoration(
                            hintText: 'AQ... ama AIza...',
                            prefixIcon: const Icon(Icons.key_rounded, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isApiKeyVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isApiKeyVisible = !_isApiKeyVisible;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Base URL
                        Text(
                          'Base URL (Ikhtiyaari)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _baseUrlController,
                          decoration: InputDecoration(
                            hintText:
                                'https://generativelanguage.googleapis.com',
                            prefixIcon: const Icon(
                              Icons.link_rounded,
                              size: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Verification Feedback Banner
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.network_check_rounded,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Hubinta Xiriirka Codka',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Hubi in furahaaga API iyo moodalka aad dooratay ay si toos ah u soo celin karaan codka akhriska.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _isTesting
                                    ? null
                                    : _runTtsVerification,
                                icon: _isTesting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.volume_up_rounded,
                                        size: 17,
                                      ),
                                label: Text(
                                  _isTesting
                                      ? 'Waa la hubinayaa...'
                                      : 'Hubi Xiriirka Codka Hadda',
                                ),
                              ),
                              if (_testFeedbackMessage != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _testSucceeded == true
                                        ? const Color(0xFFE8F5E9)
                                        : const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _testSucceeded == true
                                          ? const Color(0xFF81C784)
                                          : const Color(0xFFE57373),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _testSucceeded == true
                                            ? Icons.check_circle_rounded
                                            : Icons.error_rounded,
                                        size: 18,
                                        color: _testSucceeded == true
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFFC62828),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _testFeedbackMessage!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _testSucceeded == true
                                                ? const Color(0xFF1B5E20)
                                                : const Color(0xFFB71C1C),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Dialog Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Ka noqo'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _isTesting ? null : _submitSave,
                      icon: Icon(
                        _testSucceeded == true
                            ? Icons.check_circle_outline
                            : Icons.check,
                        size: 18,
                      ),
                      label: Text(
                        _testSucceeded == true
                            ? 'Keydi & Fasax Codka'
                            : 'Keydi Model-ka Codka',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        backgroundColor: _testSucceeded == true
                            ? const Color(0xFF2E7D32)
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
