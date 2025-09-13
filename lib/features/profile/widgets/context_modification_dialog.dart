import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/primary_gradient_button.dart';
import '../../../data/models/therapy_context.dart';

class ContextModificationDialog extends StatefulWidget {
  final TherapyContext therapyContext;
  final Function(Map<String, dynamic>) onSave;

  const ContextModificationDialog({
    super.key,
    required this.therapyContext,
    required this.onSave,
  });

  @override
  State<ContextModificationDialog> createState() =>
      _ContextModificationDialogState();
}

class _ContextModificationDialogState extends State<ContextModificationDialog> {
  bool _hasShownWarning = false;
  bool _isEditing = false;

  // Controllers for editing
  final _moodPatternsController = TextEditingController();
  final _stressTriggersController = TextEditingController();
  final _copingStrategiesController = TextEditingController();
  final _progressAreasController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _populateControllers();
  }

  void _populateControllers() {
    _moodPatternsController.text = widget.therapyContext.moodPatterns ?? '';
    _stressTriggersController.text = widget.therapyContext.stressTriggers ?? '';
    _copingStrategiesController.text =
        widget.therapyContext.copingStrategies ?? '';
    _progressAreasController.text = widget.therapyContext.progressAreas ?? '';
  }

  @override
  void dispose() {
    _moodPatternsController.dispose();
    _stressTriggersController.dispose();
    _copingStrategiesController.dispose();
    _progressAreasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasShownWarning) {
      return _buildWarningDialog();
    }

    if (!_isEditing) {
      return _buildContextDisplayDialog();
    }

    return _buildEditDialog();
  }

  Widget _buildWarningDialog() {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning, color: Colors.orange, size: 28),
          const SizedBox(width: 8),
          const Text('Important Warning'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You are about to modify what the AI knows about you therapeutically.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            '⚠️ This information directly affects how the AI therapist responds to you.',
          ),
          const SizedBox(height: 8),
          const Text(
            '⚠️ Changes may alter the therapeutic approach and recommendations.',
          ),
          const SizedBox(height: 8),
          const Text(
            '⚠️ Only modify if you believe the current information is incorrect.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: const Text(
              'Current AI Knowledge:\n'
              '• Mood patterns and triggers\n'
              '• Effective coping strategies\n'
              '• Progress areas and insights',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _hasShownWarning = true;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: const Text('I Understand, Continue'),
        ),
      ],
    );
  }

  Widget _buildContextDisplayDialog() {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.psychology, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Current AI Knowledge',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isEditing = true;
                      });
                    },
                    tooltip: 'Edit context',
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.therapyContext.therapyContext != null) ...[
                      _buildContextSection(
                        'Therapy Context',
                        widget.therapyContext.therapyContext!,
                        Icons.psychology,
                        Colors.purple,
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (widget.therapyContext.aiInsights != null) ...[
                      _buildContextSection(
                        'AI Insights',
                        widget.therapyContext.aiInsights!,
                        Icons.insights,
                        Colors.green,
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Last updated
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Last updated: ${_formatDate(widget.therapyContext.lastUpdated)}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditDialog() {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Edit AI Knowledge',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Edit the information that the AI uses to understand you better:',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),

                    // Mood Patterns
                    _buildEditField(
                      'Mood Patterns',
                      'How do you typically feel throughout the day?',
                      _moodPatternsController,
                      Icons.mood,
                    ),
                    const SizedBox(height: 16),

                    // Stress Triggers
                    _buildEditField(
                      'Stress Triggers',
                      'What situations or events cause you stress?',
                      _stressTriggersController,
                      Icons.flash_on,
                    ),
                    const SizedBox(height: 16),

                    // Coping Strategies
                    _buildEditField(
                      'Effective Coping Strategies',
                      'What helps you when you\'re feeling overwhelmed?',
                      _copingStrategiesController,
                      Icons.self_improvement,
                    ),
                    const SizedBox(height: 16),

                    // Progress Areas
                    _buildEditField(
                      'Progress Areas',
                      'What improvements have you noticed?',
                      _progressAreasController,
                      Icons.trending_up,
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isEditing = false;
                        _populateControllers(); // Reset to original values
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  PrimaryGradientButton(
                    onPressed: _saveChanges,
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextSection(
    String title,
    Map<String, dynamic> data,
    IconData icon,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...data.entries.map((entry) {
          final key = entry.key
              .replaceAll('_', ' ')
              .split(' ')
              .map(
                (word) =>
                    word.isNotEmpty
                        ? '${word[0].toUpperCase()}${word.substring(1)}'
                        : word,
              )
              .join(' ');
          final value = entry.value?.toString() ?? 'N/A';

          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEditField(
    String label,
    String hint,
    TextEditingController controller,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.primaryViolet, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryViolet,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  void _saveChanges() {
    final updatedData = <String, dynamic>{
      'therapy_context': {
        'mood_patterns': _moodPatternsController.text.trim(),
        'stress_triggers': _stressTriggersController.text.trim(),
      },
      'ai_insights': {
        'coping_strategies': _copingStrategiesController.text.trim(),
        'progress_areas': _progressAreasController.text.trim(),
      },
    };

    widget.onSave(updatedData);
    Navigator.of(context).pop();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
