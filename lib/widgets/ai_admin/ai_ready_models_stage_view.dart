import 'package:flutter/material.dart';

import '../../models/ai_model_config.dart';
import '../../services/ai_model_storage.dart';

class AiReadyModelsStageView extends StatefulWidget {
  const AiReadyModelsStageView({
    super.key,
    this.storage = const AiModelStorage(),
    this.onGoToRouting,
    this.onRetestModel,
  });

  final AiModelStorage storage;
  final VoidCallback? onGoToRouting;
  final void Function(AiModelConfig model)? onRetestModel;

  @override
  State<AiReadyModelsStageView> createState() => _AiReadyModelsStageViewState();
}

class _AiReadyModelsStageViewState extends State<AiReadyModelsStageView> {
  List<AiModelConfig> _readyChatModels = [];
  List<AiModelConfig> _readyTtsModels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReadyModels();
  }

  Future<void> _loadReadyModels() async {
    setState(() => _isLoading = true);
    final chat = await widget.storage.getModels();
    final tts = await widget.storage.getTtsModels();
    if (!mounted) return;
    setState(() {
      _readyChatModels = chat.where((m) => m.status == 'ready').toList();
      _readyTtsModels = tts.where((m) => m.status == 'ready').toList();
      _isLoading = false;
    });
  }

  Future<void> _toggleModelActive(AiModelConfig model, bool isTts) async {
    final updated = model.copyWith(isActive: !model.isActive);
    if (isTts) {
      await widget.storage.saveTtsModel(updated);
    } else {
      await widget.storage.saveModel(updated);
    }
    await _loadReadyModels();
  }

  Future<void> _revertToTesting(AiModelConfig model, bool isTts) async {
    await widget.storage.sendModelToTesting(model.id, isTts: isTts);
    await _loadReadyModels();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Model-ka "${model.displayName}" waxaa dib loogu celiyay Qaybta Tijaabada.'),
      ),
    );
    widget.onRetestModel?.call(model);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalReady = _readyChatModels.length + _readyTtsModels.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Banner
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
                  color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF16A34A),
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Models-ka Diyaar-ka ah ($totalReady Models)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Halkan waxaa ku jira kaliya moodellada kasoo gudbay tijaabada (Stage 2) ee la xaqiijiyay. Moodelladan waxaa loo qoondeyn karaa nidaamka Automatic Routing-ka ee app-ka.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: widget.onGoToRouting,
                icon: const Icon(Icons.alt_route_rounded, size: 18),
                label: const Text('U Gudub App Routing-ka (Stage 4)'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0022FF),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Ready Models List
        if (totalReady == 0)
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
                Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  'Ma jiraan moodello hadda diyaar ah',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tag Qaybta 1 (Models) kadibna u gudbi Qaybta 2 (Test) si aad u xaqiijiso.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: ListView(
              children: [
                if (_readyChatModels.isNotEmpty) ...[
                  const Text(
                    'Chat & LLM Models (Diyaar ah)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._readyChatModels.map((m) => _buildReadyModelCard(m, false)),
                  const SizedBox(height: 16),
                ],
                if (_readyTtsModels.isNotEmpty) ...[
                  const Text(
                    'Codadka TTS (Diyaar ah)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._readyTtsModels.map((m) => _buildReadyModelCard(m, true)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildReadyModelCard(AiModelConfig model, bool isTts) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
          // Icon Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
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
                      model.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                    const SizedBox(width: 6),
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
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Model ID: ${model.modelId} • Diyaar u ah isticmaalka ardayda',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Actions
          OutlinedButton.icon(
            onPressed: () => _revertToTesting(model, isTts),
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('Dib u Tijaabi'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 12),

          // Active Switch
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                model.isActive ? 'Firfircoon' : 'Dami',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: model.isActive ? const Color(0xFF16A34A) : Colors.grey,
                ),
              ),
              const SizedBox(width: 6),
              Switch(
                value: model.isActive,
                activeColor: const Color(0xFF16A34A),
                onChanged: (_) => _toggleModelActive(model, isTts),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
