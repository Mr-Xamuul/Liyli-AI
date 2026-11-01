import 'package:flutter/material.dart';

import '../../models/ai_model_config.dart';
import '../../models/ai_routing_config.dart';
import '../../services/ai_model_storage.dart';
import '../../services/ai_routing_storage.dart';

class AiRoutingStageView extends StatefulWidget {
  const AiRoutingStageView({
    super.key,
    this.storage = const AiModelStorage(),
    this.routingStorage = const AiRoutingStorage(),
  });

  final AiModelStorage storage;
  final AiRoutingStorage routingStorage;

  @override
  State<AiRoutingStageView> createState() => _AiRoutingStageViewState();
}

class _AiRoutingStageViewState extends State<AiRoutingStageView> {
  AiRoutingConfig? _config;
  List<AiModelConfig> _allReadyModels = [];
  List<AiModelConfig> _allReadyTtsModels = [];
  bool _isLoading = true;
  bool _isSimulating = false;
  String? _simulationResult;
  bool _isSimulatingTts = false;
  String? _ttsSimulationResult;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final config = await widget.routingStorage.getConfig();
    final all = await widget.storage.getModels();
    final allTts = await widget.storage.getTtsModels();
    if (!mounted) return;
    setState(() {
      _config = config;
      _allReadyModels =
          all.where((m) => m.status == 'ready' && m.isActive).toList();
      _allReadyTtsModels =
          allTts.where((m) => m.status == 'ready' && m.isActive).toList();
      _isLoading = false;
    });
  }

  Future<void> _saveConfig(AiRoutingConfig updated) async {
    setState(() => _config = updated);
    await widget.routingStorage.saveConfig(updated);
  }

  void _moveFreeModel(int oldIndex, int newIndex) {
    if (_config == null) return;
    final list = List<String>.from(_config!.freeModelIds);
    if (newIndex < 0 || newIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _saveConfig(_config!.copyWith(freeModelIds: list));
  }

  void _movePaidModel(int oldIndex, int newIndex) {
    if (_config == null) return;
    final list = List<String>.from(_config!.paidModelIds);
    if (newIndex < 0 || newIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _saveConfig(_config!.copyWith(paidModelIds: list));
  }

  void _removeFreeModel(String id) {
    if (_config == null) return;
    final list = List<String>.from(_config!.freeModelIds)..remove(id);
    _saveConfig(_config!.copyWith(freeModelIds: list));
  }

  void _removePaidModel(String id) {
    if (_config == null) return;
    final list = List<String>.from(_config!.paidModelIds)..remove(id);
    _saveConfig(_config!.copyWith(paidModelIds: list));
  }

  Future<void> _showAddModelDialog(bool isFreeTier) async {
    final currentIds = isFreeTier
        ? (_config?.freeModelIds ?? [])
        : (_config?.paidModelIds ?? []);

    final available = _allReadyModels
        .where((m) => !currentIds.contains(m.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dhammaan moodellada diyaar-ka ah mar hore ayaa lagu daray safkan.',
          ),
        ),
      );
      return;
    }

    final selected = await showDialog<AiModelConfig>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isFreeTier ? 'Ku dar Model Safka Bilaashka' : 'Ku dar Model Safka Lacagta',
        ),
        content: SizedBox(
          width: 420,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: available.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final model = available[idx];
              return ListTile(
                leading: const Icon(Icons.smart_toy_rounded, color: Color(0xFF0022FF)),
                title: Text(model.displayName),
                subtitle: Text('${model.company} • ${model.modelId}'),
                onTap: () => Navigator.pop(ctx, model),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Jooji'),
          ),
        ],
      ),
    );

    if (selected != null && _config != null) {
      if (isFreeTier) {
        final list = List<String>.from(_config!.freeModelIds)..add(selected.id);
        await _saveConfig(_config!.copyWith(freeModelIds: list));
      } else {
        final list = List<String>.from(_config!.paidModelIds)..add(selected.id);
        await _saveConfig(_config!.copyWith(paidModelIds: list));
      }
    }
  }

  Future<void> _simulateFailover() async {
    if (_config == null) return;
    setState(() {
      _isSimulating = true;
      _simulationResult = null;
    });

    await Future.delayed(const Duration(milliseconds: 700));

    final targetIds = _config!.activeTier == 'paid'
        ? _config!.paidModelIds
        : _config!.freeModelIds;

    if (targetIds.length < 2) {
      setState(() {
        _isSimulating = false;
        _simulationResult =
            '⚠️ Safkan wuxuu leeyahay 1 model kaliya. Ku dar model labaad si aad u tijaabiso failover-ka automatic-ka ah.';
      });
      return;
    }

    final primary = _allReadyModels.where((m) => m.id == targetIds[0]).firstOrNull;
    final secondary = _allReadyModels.where((m) => m.id == targetIds[1]).firstOrNull;

    final primaryName = primary?.displayName ?? targetIds[0];
    final secondaryName = secondary?.displayName ?? targetIds[1];

    await widget.routingStorage.recordFailover(
      failedModelName: primaryName,
      fallbackModelName: secondaryName,
      reason: 'Rate limit 429 Overloaded (Simulation)',
    );

    final updated = await widget.routingStorage.getConfig();

    if (!mounted) return;
    setState(() {
      _config = updated;
      _isSimulating = false;
      _simulationResult =
          '✅ GUUL: Xiliga ciriiriga, nidaamku wuxuu si automatic ah uga wareegay "$primaryName" ➔ "$secondaryName" ardayguna ma dareemin wax cilad ah!';
    });
  }

  void _moveTtsModel(int oldIndex, int newIndex) {
    if (_config == null) return;
    final list = List<String>.from(_config!.ttsModelIds);
    if (newIndex < 0 || newIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _saveConfig(_config!.copyWith(ttsModelIds: list));
  }

  void _removeTtsModel(String id) {
    if (_config == null) return;
    final list = List<String>.from(_config!.ttsModelIds)..remove(id);
    _saveConfig(_config!.copyWith(ttsModelIds: list));
  }

  Future<void> _showAddTtsModelDialog() async {
    final currentIds = _config?.ttsModelIds ?? [];
    final available = _allReadyTtsModels
        .where((m) => !currentIds.contains(m.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dhammaan moodellada codka ee diyaarka ah mar hore ayaa lagu daray safka TTS.',
          ),
        ),
      );
      return;
    }

    final selected = await showDialog<AiModelConfig>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.record_voice_over_rounded, color: Color(0xFF7C3AED)),
            SizedBox(width: 8),
            Text('Ku dar Model Safka Codka (TTS)'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dooro model-ka codka ee aad rabto in lagu daro safka akhriska TTS-ka:',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: available.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final model = available[idx];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.volume_up_rounded,
                            color: Color(0xFF7C3AED)),
                      ),
                      title: Text(model.displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13.5)),
                      subtitle: Text('${model.company} • ${model.modelId}',
                          style: const TextStyle(fontSize: 11.5)),
                      onTap: () => Navigator.pop(ctx, model),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Jooji'),
          ),
        ],
      ),
    );

    if (selected != null && _config != null) {
      final list = List<String>.from(_config!.ttsModelIds)..add(selected.id);
      await _saveConfig(_config!.copyWith(ttsModelIds: list));
    }
  }

  Future<void> _simulateTtsFailover() async {
    if (_config == null) return;
    setState(() {
      _isSimulatingTts = true;
      _ttsSimulationResult = null;
    });

    await Future.delayed(const Duration(milliseconds: 700));

    final targetIds = _config!.ttsModelIds;

    if (targetIds.length < 2) {
      setState(() {
        _isSimulatingTts = false;
        _ttsSimulationResult =
            '⚠️ Safka codku wuxuu leeyahay 1 model kaliya. Ku dar model codka labaad si aad u tijaabiso TTS failover-ka automatic-ka ah.';
      });
      return;
    }

    final primary =
        _allReadyTtsModels.where((m) => m.id == targetIds[0]).firstOrNull;
    final secondary =
        _allReadyTtsModels.where((m) => m.id == targetIds[1]).firstOrNull;

    final primaryName = primary?.displayName ?? targetIds[0];
    final secondaryName = secondary?.displayName ?? targetIds[1];

    await widget.routingStorage.recordTtsFailover(
      failedModelName: primaryName,
      fallbackModelName: secondaryName,
      reason: 'Audio Quota Limit Exceeded / Network Timeout (Simulation)',
    );

    final updated = await widget.routingStorage.getConfig();

    if (!mounted) return;
    setState(() {
      _config = updated;
      _isSimulatingTts = false;
      _ttsSimulationResult =
          '✅ GUUL: Xiliga cilladda codka, nidaamku wuxuu si automatic ah uga wareegay "$primaryName" ➔ "$secondaryName" si ardaydu u helaan akhrin joogto ah!';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _config == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final config = _config!;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Overview
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
                    color: const Color(0xFF0022FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.alt_route_rounded,
                    color: Color(0xFF0022FF),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nidaamka Automatic-ka & Isticmaalka App-ka (Stage 4)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Halkan waxaad ku maamulaysaa sida uu app-ku u isticmaalayo moodellada si automatic ah. '
                        'Xiliga ciriiriga ama quota limit-ka, nidaamku si automatic ah ayuu ugu wareegayaa model-ka xiga ee safka ku jira.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Global Automation Controls Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dejinta Nidaamka Guud (Automation Engine)',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Ciriiri Ka-hortag Automatic ah (Auto-Failover)'),
                  subtitle: const Text(
                    'Haddii model-ka koowaad uu mashquulo ama limit galo (HTTP 429), si toos ah ugu gudub model-ka xiga.',
                  ),
                  value: config.autoFallbackEnabled,
                  activeThumbColor: const Color(0xFF16A34A),
                  onChanged: (val) =>
                      _saveConfig(config.copyWith(autoFallbackEnabled: val)),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(height: 16),
                SwitchListTile(
                  title: const Text('Qari Doorashada Model-ka ee Topbar-ka Chat-ka'),
                  subtitle: const Text(
                    'Qari badhanka doorashada model-ka si ardaydu aysan gacanta ugu beddelin, nidaamkuna si automatic ah u maamulo.',
                  ),
                  value: config.hideModelPickerFromChat,
                  activeThumbColor: const Color(0xFF0022FF),
                  onChanged: (val) =>
                      _saveConfig(config.copyWith(hideModelPickerFromChat: val)),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    const Text(
                      'Heerka Hadda Firfircoon ee App-ka (Current Tier):',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 14),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'free',
                          label: Text('Bilaash (Free Tier)'),
                          icon: Icon(Icons.people_outline_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: 'paid',
                          label: Text('Lacagta (Paid / VIP)'),
                          icon: Icon(Icons.star_rounded, size: 16),
                        ),
                      ],
                      selected: {config.activeTier},
                      onSelectionChanged: (set) {
                        _saveConfig(config.copyWith(activeTier: set.first));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Two-Column Priority Pools: Free Tier vs Paid Tier
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 800;

              final freePoolWidget = _buildTierPoolCard(
                title: '1. Safka Bilaashka ah (Free Tier Pool)',
                subtitle: 'Moodellada ay isticmaalaan dhammaan ardayda guud',
                badgeColor: const Color(0xFF16A34A),
                isFreeTier: true,
                modelIds: config.freeModelIds,
              );

              final paidPoolWidget = _buildTierPoolCard(
                title: '2. Safka Lacagta / VIP (Paid Tier Pool)',
                subtitle: 'Moodellada xawaaraha sarreeya ee ardayda lacagta bixiyay',
                badgeColor: const Color(0xFFD97706),
                isFreeTier: false,
                modelIds: config.paidModelIds,
              );

              if (isNarrow) {
                return Column(
                  children: [
                    freePoolWidget,
                    const SizedBox(height: 16),
                    paidPoolWidget,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: freePoolWidget),
                  const SizedBox(width: 16),
                  Expanded(child: paidPoolWidget),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Failover Simulator Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFFEA580C),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tijaabi Ciriiri Ka-hortagga (Failover Simulation)',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'U ekaysii xaalad ciriiri ah si aad u aragto sida uu nidaamku ugu wareegayo model-ka xiga',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _isSimulating ? null : _simulateFailover,
                      icon: _isSimulating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(_isSimulating ? 'Tijaabinayaa...' : 'Simulate Failover'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEA580C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_simulationResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Text(
                      _simulationResult!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (config.lastFailoverReason != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.history_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        'Xogtii ugu dambaysay ee Failover: ${config.lastFailoverReason}',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Dedicated Unified Voice & TTS Routing Card
          _buildTtsRoutingCard(config),
        ],
      ),
    );
  }

  /// Dedicated TTS Routing Section - completely separate from chat models
  /// Unified pool for ALL students (no free vs paid separation)
  Widget _buildTtsRoutingCard(AiRoutingConfig config) {
    const ttsPrimaryColor = Color(0xFF7C3AED);
    final modelIds = config.ttsModelIds;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ttsPrimaryColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: ttsPrimaryColor.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ttsPrimaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.record_voice_over_rounded,
                  color: ttsPrimaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '3. Maamulka Safka Codka / TTS Routing',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: ttsPrimaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: ttsPrimaryColor.withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'Dhammaan Ardayda (Unified Pool)',
                            style: TextStyle(
                              color: ttsPrimaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Safkaan waa mid u gaar ah codka oo keliya (TTS) lagumana dhex daro chat-ka. '
                      'Dhammaan ardaydu (Bilaash & VIP) waxay wadaagaan hal meel oo codka ah. '
                      'Codka waxaa lagu akhrinayaa oo keliya moodellada aad halkan ku diyaariso iyadoo loo raacayo sida aad u kala hor marisay.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _showAddTtsModelDialog,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Ku dar Model Codka'),
                style: FilledButton.styleFrom(
                  backgroundColor: ttsPrimaryColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // TTS Auto-failover Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFBFBFE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SwitchListTile(
              title: const Text(
                'Ciriiri Ka-hortagga Codka (TTS Auto-Failover)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Haddii codka koowaad uu shaqeyn waayo, cilladoobo ama limit galo, si toos ah ugu wareeg codka xiga ee safka.',
                style: TextStyle(fontSize: 11.5),
              ),
              value: config.ttsAutoFallbackEnabled,
              activeThumbColor: ttsPrimaryColor,
              onChanged: (val) =>
                  _saveConfig(config.copyWith(ttsAutoFallbackEnabled: val)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 14),

          // Models List
          if (modelIds.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.mic_off_rounded,
                      size: 32, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'Ma jiro model codka ah (TTS) oo safka ku jira.',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Guji "Ku dar Model Codka" si aad ugu darto moodellada aad ku diyaarisay Qaybta 3 (Ready Models).',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: modelIds.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final id = modelIds[idx];
                final model =
                    _allReadyTtsModels.where((m) => m.id == id).firstOrNull;
                final isPrimary = idx == 0;
                final isLast = idx == modelIds.length - 1;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? ttsPrimaryColor.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPrimary
                          ? ttsPrimaryColor.withValues(alpha: 0.4)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Priority Rank Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPrimary
                              ? ttsPrimaryColor
                              : Colors.grey.shade600,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isPrimary
                              ? '1. Codka Koowaad (Primary)'
                              : '${idx + 1}. Codka Kaydka (Fallback)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Model Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model?.displayName ?? id,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (model != null)
                              Text(
                                '${model.company} • ${model.modelId}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Move Up
                      IconButton(
                        tooltip: 'Kor u qaad (Kordhi mudnaanta)',
                        icon:
                            const Icon(Icons.arrow_upward_rounded, size: 17),
                        visualDensity: VisualDensity.compact,
                        onPressed: idx > 0
                            ? () => _moveTtsModel(idx, idx - 1)
                            : null,
                      ),

                      // Move Down
                      IconButton(
                        tooltip: 'Hoos u dhig (Yaree mudnaanta)',
                        icon: const Icon(Icons.arrow_downward_rounded,
                            size: 17),
                        visualDensity: VisualDensity.compact,
                        onPressed: !isLast
                            ? () => _moveTtsModel(idx, idx + 1)
                            : null,
                      ),

                      // Delete from queue
                      IconButton(
                        tooltip: 'Ka saar safka codka',
                        icon: const Icon(Icons.close_rounded,
                            size: 17, color: Colors.red),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeTtsModel(id),
                      ),
                    ],
                  ),
                );
              },
            ),

          const SizedBox(height: 16),

          // TTS Failover Simulator Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ttsPrimaryColor.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: ttsPrimaryColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded,
                        color: ttsPrimaryColor, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Tijaabi Kala-wareegga Codka (TTS Failover Simulator)',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B)),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          _isSimulatingTts ? null : _simulateTtsFailover,
                      icon: _isSimulatingTts
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ttsPrimaryColor,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 16),
                      label: Text(_isSimulatingTts
                          ? 'Tijaabinayaa...'
                          : 'Tijaabi Codka'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            ttsPrimaryColor.withValues(alpha: 0.15),
                        foregroundColor: ttsPrimaryColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ),
                if (_ttsSimulationResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Text(
                      _ttsSimulationResult!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (config.lastTtsFailoverReason != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.history_rounded,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Xogtii ugu dambaysay ee Codka: ${config.lastTtsFailoverReason}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierPoolCard({
    required String title,
    required String subtitle,
    required Color badgeColor,
    required bool isFreeTier,
    required List<String> modelIds,
  }) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showAddModelDialog(isFreeTier),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Ku dar Model'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (modelIds.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'Ma jiro model safkan ku jira. Guji "Ku dar Model" si aad u bilowdo.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: modelIds.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final id = modelIds[idx];
                final model = _allReadyModels.where((m) => m.id == id).firstOrNull;
                final isPrimary = idx == 0;
                final isLast = idx == modelIds.length - 1;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? badgeColor.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPrimary
                          ? badgeColor.withValues(alpha: 0.4)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Priority Rank Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isPrimary ? badgeColor : Colors.grey.shade600,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isPrimary ? '1. Primary' : '${idx + 1}. Fallback',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Model Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model?.displayName ?? id,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (model != null)
                              Text(
                                '${model.company} • ${model.modelId}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Move Up
                      IconButton(
                        tooltip: 'Kor u qaad',
                        icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                        visualDensity: VisualDensity.compact,
                        onPressed: idx > 0
                            ? () {
                                if (isFreeTier) {
                                  _moveFreeModel(idx, idx - 1);
                                } else {
                                  _movePaidModel(idx, idx - 1);
                                }
                              }
                            : null,
                      ),

                      // Move Down
                      IconButton(
                        tooltip: 'Hoos u dhig',
                        icon: const Icon(Icons.arrow_downward_rounded, size: 17),
                        visualDensity: VisualDensity.compact,
                        onPressed: !isLast
                            ? () {
                                if (isFreeTier) {
                                  _moveFreeModel(idx, idx + 1);
                                } else {
                                  _movePaidModel(idx, idx + 1);
                                }
                              }
                            : null,
                      ),

                      // Delete from queue
                      IconButton(
                        tooltip: 'Ka saar safka',
                        icon: const Icon(Icons.close_rounded, size: 17, color: Colors.red),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          if (isFreeTier) {
                            _removeFreeModel(id);
                          } else {
                            _removePaidModel(id);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
