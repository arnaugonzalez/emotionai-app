import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import 'package:emotion_ai/data/models/custom_emotion.dart';
import 'package:emotion_ai/data/models/emotional_record.dart';
import 'package:emotion_ai/features/auth/auth_provider.dart';
import 'package:emotion_ai/shared/providers/app_providers.dart' show apiServiceProvider;
import 'package:emotion_ai/utils/color_utils.dart';
import '../../features/custom_emotion/custom_emotion_dialog.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class StandardEmotion {
  final String name;
  final Color color;
  StandardEmotion(this.name, this.color);
}

final standardEmotions = [
  StandardEmotion('Happy', Colors.yellow),
  StandardEmotion('Excited', Colors.orange),
  StandardEmotion('Tender', Colors.pink),
  StandardEmotion('Scared', Colors.purple),
  StandardEmotion('Angry', Colors.red),
  StandardEmotion('Sad', Colors.blue),
  StandardEmotion('Anxious', Colors.teal),
];

class ColorWheelScreen extends ConsumerStatefulWidget {
  const ColorWheelScreen({super.key});

  @override
  ConsumerState<ColorWheelScreen> createState() => _ColorWheelScreenState();
}

class _ColorWheelScreenState extends ConsumerState<ColorWheelScreen> {
  final List<CustomEmotion> customEmotions = [];
  final List<CustomEmotion> shuffledCustomEmotions = [];
  final Random _random = Random();
  dynamic selectedEmotion;
  bool isCustomEmotion = false;

  @override
  void initState() {
    super.initState();
    selectedEmotion = standardEmotions.first; // Default selection
    _loadCustomEmotions();
  }

  Future<void> _loadCustomEmotions() async {
    final apiService = ref.read(apiServiceProvider);
    final emotions = await apiService.getCustomEmotions();
    final shuffled = List<CustomEmotion>.from(emotions);
    _shuffleList(shuffled);

    setState(() {
      customEmotions.clear();
      customEmotions.addAll(emotions);
      shuffledCustomEmotions.clear();
      shuffledCustomEmotions.addAll(shuffled);
    });
  }

  Future<void> _addCustomEmotion() async {
    final result = await showDialog<CustomEmotion>(
      context: context,
      builder: (context) => const CustomEmotionDialog(),
    );

    if (result != null) {
      final apiService = ref.read(apiServiceProvider);
      await apiService.createCustomEmotion(result);
      await _loadCustomEmotions();
      setState(() {
        isCustomEmotion = true;
        selectedEmotion = result;
      });
    }
  }

  void _shuffleList<T>(List<T> list) {
    for (int i = list.length - 1; i > 0; i--) {
      int j = _random.nextInt(i + 1);
      // Swap elements
      T temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  Future<void> saveEmotionalRecord(EmotionalRecord record) async {
    final apiService = ref.read(apiServiceProvider);
    await apiService.createEmotionalRecord(record);
  }

  @override
  Widget build(BuildContext context) {
    // Remove the shuffling here since we're now using the pre-shuffled list

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'How do you feel today?',
                style: TextStyle(fontSize: 28),
                textAlign: TextAlign.center,
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
              const SizedBox(height: 20),

              // Emotion type selector
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Standard'),
                      selected: !isCustomEmotion,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            isCustomEmotion = false;
                            selectedEmotion = standardEmotions.first;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    ChoiceChip(
                      label: const Text('Custom'),
                      selected: isCustomEmotion,
                      onSelected: (selected) {
                        if (selected) {
                          if (customEmotions.isNotEmpty) {
                            setState(() {
                              isCustomEmotion = true;
                              selectedEmotion = customEmotions.first;
                            });
                          } else {
                            _addCustomEmotion();
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      tooltip: 'Add custom emotion',
                      onPressed: _addCustomEmotion,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Standard emotions wheel
              if (!isCustomEmotion)
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width,
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children:
                        standardEmotions.map((emotion) {
                          final isSelected = selectedEmotion == emotion;
                          return ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 120,
                              minHeight: 40,
                            ),
                            child: ChoiceChip(
                              label: Text(
                                emotion.name.toUpperCase(),
                                style: TextStyle(
                                  color:
                                      isSelected ? Colors.white : Colors.black,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                              selected: isSelected,
                              selectedColor: emotion.color,
                              backgroundColor: emotion.color.withValues(
                                alpha: 0.8,
                              ),
                              onSelected: (_) {
                                setState(() {
                                  selectedEmotion = emotion;
                                });
                              },
                            ),
                          );
                        }).toList(),
                  ),
                ),

              // Custom emotions wheel
              if (isCustomEmotion)
                customEmotions.isEmpty
                    ? const Text(
                      'No custom emotions yet. Add one using the + button above.',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    )
                    : Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width,
                      ),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children:
                            customEmotions.map((emotion) {
                              final isSelected = selectedEmotion == emotion;
                              return ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 120,
                                  minHeight: 40,
                                ),
                                child: ChoiceChip(
                                  label: Text(
                                    emotion.name,
                                    style: TextStyle(
                                      color:
                                          isSelected
                                              ? Colors.white
                                              : Colors.black,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                  selected: isSelected,
                                  selectedColor: ColorHelper.fromDatabaseColor(emotion.color),
                                  backgroundColor: ColorHelper.fromDatabaseColor(emotion.color).withValues(alpha: 0.8),
                                  onSelected: (_) {
                                    setState(() {
                                      selectedEmotion = emotion;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                      ),
                    ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      selectedEmotion != null
                          ? () async {
                            final now = DateTime.now();

                            if (isCustomEmotion) {
                              // For custom emotions
                              final customEmotion =
                                  selectedEmotion as CustomEmotion;
                              final record = EmotionalRecord(
                                source: 'color_wheel',
                                description:
                                    'Selected custom emotion: ${customEmotion.name}',
                                emotion: customEmotion.name,
                                color: customEmotion.color,
                                customEmotionName: customEmotion.name,
                                customEmotionColor: customEmotion.color,
                                createdAt: now,
                              );

                              try {
                                await saveEmotionalRecord(record);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Custom emotion saved: ${customEmotion.name}',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to save emotion'),
                                  ),
                                );
                              }
                            } else {
                              // For standard emotions
                              final stdEmotion =
                                  selectedEmotion as StandardEmotion;
                              final record = EmotionalRecord(
                                source: 'color_wheel',
                                description:
                                    'Selected directly from the color wheel',
                                emotion: stdEmotion.name,
                                color: stdEmotion.color.toARGB32(),
                                createdAt: now,
                              );

                              try {
                                await saveEmotionalRecord(record);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Emotion saved: ${stdEmotion.name}',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to save emotion'),
                                  ),
                                );
                              }
                            }
                          }
                          : null,
                  child: const Text('Save Emotion'),
                ),
              ),

              // Display custom emotions in random order at bottom
              if (customEmotions.isNotEmpty) ...[
                const SizedBox(height: 40),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Your Custom Emotions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children:
                        shuffledCustomEmotions.map((e) {
                          return ActionChip(
                            avatar: CircleAvatar(
                              backgroundColor: ColorHelper.fromDatabaseColor(e.color),
                              radius: 12,
                            ),
                            label: Text(e.name, overflow: TextOverflow.visible),
                            onPressed: () {
                              setState(() {
                                isCustomEmotion = true;
                                selectedEmotion = e;
                              });
                            },
                          );
                        }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
