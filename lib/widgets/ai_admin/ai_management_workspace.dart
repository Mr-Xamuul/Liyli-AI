import 'package:flutter/material.dart';

import '../../models/ai_model_config.dart';
import '../../services/ai_model_storage.dart';
import '../../services/api_key_storage.dart';
import '../../services/prepared_book_storage.dart';
import 'ai_api_keys_stage_view.dart';
import 'ai_models_stage_view.dart';
import 'ai_ready_models_stage_view.dart';
import 'ai_routing_stage_view.dart';
import 'ai_test_stage_view.dart';

class AiManagementWorkspace extends StatefulWidget {
  const AiManagementWorkspace({
    super.key,
    this.initialStageIndex = 0,
    this.storage = const AiModelStorage(),
    this.keyStorage = const ApiKeyStorage(),
    this.bookStorage = const PreparedBookStorage(),
  });

  final int initialStageIndex;
  final AiModelStorage storage;
  final ApiKeyStorage keyStorage;
  final PreparedBookStorage bookStorage;

  @override
  State<AiManagementWorkspace> createState() => _AiManagementWorkspaceState();
}

class _AiManagementWorkspaceState extends State<AiManagementWorkspace> {
  late int _activeStageIndex;
  AiModelConfig? _modelBeingTested;
  int _modelsVersion = 0;
  int _readyVersion = 0;
  int _routingVersion = 0;

  @override
  void initState() {
    super.initState();
    _activeStageIndex = widget.initialStageIndex;
  }

  void _switchStage(int index) {
    setState(() {
      if (index == 0) _modelsVersion++;
      if (index == 2) _readyVersion++;
      if (index == 3) _routingVersion++;
      _activeStageIndex = index;
    });
  }

  void _onKeysChanged() {
    setState(() {
      _modelsVersion++;
    });
  }

  void _onSendToTest(AiModelConfig model, bool isTts) {
    setState(() {
      _modelBeingTested = model;
      _activeStageIndex = 1; // Switch to Stage 2: Test
    });
  }

  void _onPromotedToReady(AiModelConfig model) {
    setState(() {
      _readyVersion++;
      _routingVersion++;
      _activeStageIndex = 2; // Switch to Stage 3: Ready Models
    });
  }

  void _onRetestModel(AiModelConfig model) {
    setState(() {
      _modelBeingTested = model;
      _activeStageIndex = 1; // Switch to Stage 2: Test
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Navigation Bar with the 5 Systematic Stages
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStageTab(
                  index: 0,
                  number: '1',
                  title: 'Models',
                  subtitle: 'Habaynta & Kaydka',
                  icon: Icons.layers_rounded,
                  color: const Color(0xFF0022FF),
                ),
                _buildStageArrow(),
                _buildStageTab(
                  index: 1,
                  number: '2',
                  title: 'Test',
                  subtitle: 'Tijaabada & Qiimeynta',
                  icon: Icons.science_rounded,
                  color: const Color(0xFF0284C7),
                ),
                _buildStageArrow(),
                _buildStageTab(
                  index: 2,
                  number: '3',
                  title: 'Diyaar ah',
                  subtitle: 'Models Kasoo Gudbay',
                  icon: Icons.verified_rounded,
                  color: const Color(0xFF16A34A),
                ),
                _buildStageArrow(),
                _buildStageTab(
                  index: 3,
                  number: '4',
                  title: 'App Routing',
                  subtitle: 'Automatic & Fallback',
                  icon: Icons.alt_route_rounded,
                  color: const Color(0xFFEA580C),
                ),
                _buildStageArrow(),
                _buildStageTab(
                  index: 4,
                  number: '5',
                  title: 'API Keys',
                  subtitle: 'Kaydka Furayaasha',
                  icon: Icons.vpn_key_rounded,
                  color: const Color(0xFF7C3AED),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Stage View Body
        Expanded(
          child: IndexedStack(
            index: _activeStageIndex,
            children: [
              // 0: Stage 1 Models
              AiModelsStageView(
                key: ValueKey('stage_models_$_modelsVersion'),
                storage: widget.storage,
                keyStorage: widget.keyStorage,
                onSendToTest: _onSendToTest,
              ),

              // 1: Stage 2 Test
              AiTestStageView(
                key: ValueKey('stage_test_${_modelBeingTested?.id}'),
                storage: widget.storage,
                bookStorage: widget.bookStorage,
                initialModel: _modelBeingTested,
                onPromotedToReady: _onPromotedToReady,
              ),

              // 2: Stage 3 Ready Models
              AiReadyModelsStageView(
                key: const ValueKey('stage_ready'),
                storage: widget.storage,
                onGoToRouting: () => _switchStage(3),
                onRetestModel: _onRetestModel,
              ),

              // 3: Stage 4 App Routing
              const AiRoutingStageView(
                key: ValueKey('stage_routing'),
              ),

              // 4: Stage 5 API Keys
              AiApiKeysStageView(
                key: const ValueKey('stage_api_keys'),
                storage: widget.keyStorage,
                onKeysChanged: _onKeysChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStageTab({
    required int index,
    required String number,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _activeStageIndex == index;

    return InkWell(
      onTap: () => _switchStage(index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.3) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade800,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: isSelected ? color : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? color : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isSelected ? color.withValues(alpha: 0.8) : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: Colors.grey.shade400,
      ),
    );
  }
}
