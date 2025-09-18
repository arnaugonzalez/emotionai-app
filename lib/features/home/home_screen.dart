import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emotion_ai/data/models/custom_emotion.dart';
import 'package:emotion_ai/data/models/emotional_record.dart';
import 'package:emotion_ai/shared/providers/app_providers.dart';
import '../../features/custom_emotion/custom_emotion_dialog.dart';
import '../usage/presentation/widgets/token_usage_display.dart';
import '../../shared/widgets/validation_error_widget.dart';
import 'package:emotion_ai/shared/providers/app_providers.dart'
    show apiServiceProvider;
import 'package:emotion_ai/core/theme/app_theme.dart';
import 'package:emotion_ai/shared/widgets/gradient_app_bar.dart';
import 'package:emotion_ai/shared/widgets/themed_card.dart';
import 'package:emotion_ai/shared/widgets/primary_gradient_button.dart';
import 'package:emotion_ai/utils/color_utils.dart';

// --- State Providers ---

final inputProvider = StateProvider<String>((ref) => '');
final emotionProvider = StateProvider<dynamic>((ref) => 'Happy');
final isCustomEmotionProvider = StateProvider<bool>((ref) => false);

// --- Data Providers ---

final customEmotionsProvider = FutureProvider<List<CustomEmotion>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getCustomEmotions();
});

// --- Standard Emotions ---

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

// --- HomeScreen Widget ---

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSaving = false; // Add debounce flag
  List<String> _todaySuggestions = const [];

  @override
  void initState() {
    super.initState();
    // Initial data fetch
    Future.microtask(() => ref.invalidate(customEmotionsProvider));
    // Fetch today's suggestions on screen load
    Future.microtask(() async {
      try {
        final today = DateTime.now();
        final suggestions = await ref
            .read(apiServiceProvider)
            .getDailySuggestions(today);
        if (!mounted) return;
        setState(() {
          _todaySuggestions = suggestions;
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _addCustomEmotion() async {
    final result = await showDialog<CustomEmotion>(
      context: context,
      builder: (context) => const CustomEmotionDialog(),
    );

    if (result != null) {
      try {
        final apiService = ref.read(apiServiceProvider);
        // We need to create a version of the object for the API without the ID and created_at
        final newEmotion = CustomEmotion(
          name: result.name,
          color: result.color,
          createdAt:
              DateTime.now(), // This will be ignored by the backend but required by the model
        );
        await apiService.createCustomEmotion(newEmotion);
        ref.invalidate(customEmotionsProvider);
        if (!mounted) return;
        ValidationHelper.showSuccessSnackBar(
          context,
          'Custom emotion "${result.name}" created successfully!',
        );
      } catch (e) {
        if (!mounted) return;
        ValidationHelper.showApiErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _saveRecord() async {
    // Prevent double-clicks
    if (_isSaving) return;

    final input = ref.read(inputProvider).trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter some text before saving.')),
      );
      return;
    }

    final emotionValue = ref.read(emotionProvider);
    final isCustom = ref.read(isCustomEmotionProvider);
    final apiService = ref.read(apiServiceProvider);

    // Set saving flag
    setState(() => _isSaving = true);

    try {
      // Check for duplicate input within the last 5 minutes
      final now = DateTime.now();
      final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

      try {
        // Get all records and filter locally (since API doesn't support date filtering yet)
        final allRecords = await apiService.getEmotionalRecords();
        final recentRecords =
            allRecords.where((record) {
              return record.createdAt.isAfter(fiveMinutesAgo);
            }).toList();

        // Check for exact duplicates (same text and emotion)
        final isDuplicate = recentRecords.any((record) {
          final sameText =
              record.description.toLowerCase().trim() ==
              input.toLowerCase().trim();
          final sameEmotion =
              isCustom
                  ? (emotionValue is CustomEmotion &&
                      record.customEmotionName == emotionValue.name)
                  : (record.emotion == emotionValue);
          return sameText && sameEmotion;
        });

        if (isDuplicate) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This emotional record already exists. Please wait a few minutes or modify your input.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }

        // Check for very similar inputs (fuzzy matching)
        final isSimilar = recentRecords.any((record) {
          final textSimilarity = _calculateTextSimilarity(
            record.description.toLowerCase().trim(),
            input.toLowerCase().trim(),
          );
          final sameEmotion =
              isCustom
                  ? (emotionValue is CustomEmotion &&
                      record.customEmotionName == emotionValue.name)
                  : (record.emotion == emotionValue);

          // If text is 80% similar and same emotion, consider it similar
          return textSimilarity > 0.8 && sameEmotion;
        });

        if (isSimilar) {
          final shouldContinue = await _showSimilarInputDialog(input);
          if (!shouldContinue) return;
        }
      } catch (e) {
        // If we can't check for duplicates, continue but log the error
        print('Could not check for duplicates: $e');
      }

      late EmotionalRecord record;

      if (isCustom) {
        final customEmotion = emotionValue as CustomEmotion;
        record = EmotionalRecord(
          source: 'home_input',
          description: input,
          emotion: customEmotion.name,
          color: customEmotion.color,
          customEmotionName: customEmotion.name,
          customEmotionColor: customEmotion.color,
          createdAt: DateTime.now(),
        );
      } else {
        final standardEmotion = standardEmotions.firstWhere(
          (e) => e.name == emotionValue,
        );
        record = EmotionalRecord(
          source: 'home_input',
          description: input,
          emotion: standardEmotion.name,
          color: standardEmotion.color.toARGB32(),
          createdAt: DateTime.now(),
        );
      }

      await apiService.createEmotionalRecord(record);
      // Optionally refresh today's suggestions from the API
      try {
        final today = DateTime.now();
        final suggestions = await ref
            .read(apiServiceProvider)
            .getDailySuggestions(today);
        if (mounted) {
          setState(() {
            _todaySuggestions = suggestions;
          });
        }
      } catch (_) {}
      if (!mounted) return;
      ValidationHelper.showSuccessSnackBar(
        context,
        'Record saved: ${record.emotion}',
      );
      // Clear form
      ref.read(inputProvider.notifier).state = '';
    } catch (e) {
      if (!mounted) return;
      ValidationHelper.showApiErrorSnackBar(context, e);
    } finally {
      // Reset saving flag
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // Calculate text similarity using Levenshtein distance
  double _calculateTextSimilarity(String text1, String text2) {
    if (text1 == text2) return 1.0;
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    final distance = _levenshteinDistance(text1, text2);
    final maxLength = text1.length > text2.length ? text1.length : text2.length;
    return 1.0 - (distance / maxLength);
  }

  int _levenshteinDistance(String s1, String s2) {
    final matrix = List.generate(
      s1.length + 1,
      (i) => List.generate(s2.length + 1, (j) => 0),
    );

    for (int i = 0; i <= s1.length; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= s2.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[s1.length][s2.length];
  }

  Future<bool> _showSimilarInputDialog(String input) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Similar Input Detected'),
                content: Text(
                  'We found a similar emotional record. Your input: "$input"\n\n'
                  'This might be a duplicate. Do you want to continue saving?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save Anyway'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final customEmotionsAsync = ref.watch(customEmotionsProvider);
    final isCustom = ref.watch(isCustomEmotionProvider);
    final selectedEmotion = ref.watch(emotionProvider);

    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GradientAppBar(title: 'Home'),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ThemedCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Share how you feel today',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium?.copyWith(
                                    color: AppTheme.primaryViolet,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                decoration: const InputDecoration(
                                  labelText:
                                      'Write how you feel, any thought, or something you want to share',
                                  prefixIcon: Icon(Icons.edit_outlined),
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.auto,
                                ),
                                initialValue: ref.watch(inputProvider),
                                onChanged:
                                    (value) =>
                                        ref.read(inputProvider.notifier).state =
                                            value,
                                maxLines: null,
                                minLines: 3,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: const TextStyle(fontSize: 16),
                                textInputAction: TextInputAction.newline,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ThemedCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('Standard'),
                                  selected: !isCustom,
                                  onSelected: (selected) {
                                    if (selected) {
                                      ref
                                          .read(
                                            isCustomEmotionProvider.notifier,
                                          )
                                          .state = false;
                                      ref.read(emotionProvider.notifier).state =
                                          standardEmotions.first.name;
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('Custom'),
                                  selected: isCustom,
                                  onSelected: (selected) {
                                    if (selected) {
                                      customEmotionsAsync.when(
                                        data: (customEmotions) {
                                          if (customEmotions.isNotEmpty) {
                                            ref
                                                .read(
                                                  isCustomEmotionProvider
                                                      .notifier,
                                                )
                                                .state = true;
                                            ref
                                                .read(emotionProvider.notifier)
                                                .state = customEmotions.first;
                                          } else {
                                            _addCustomEmotion();
                                          }
                                        },
                                        loading: () {},
                                        error: (e, s) {},
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
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
                        const SizedBox(height: 16),
                        if (isCustom)
                          customEmotionsAsync.when(
                            data: (customEmotions) {
                              if (customEmotions.isEmpty) {
                                return const Text(
                                  'No custom emotions yet. Add one!',
                                );
                              }

                              // Find the best matching emotion value
                              CustomEmotion? dropdownValue;
                              if (selectedEmotion is CustomEmotion) {
                                // Try to find the exact emotion in the list
                                dropdownValue = customEmotions.firstWhere(
                                  (e) => e == selectedEmotion,
                                  orElse: () => customEmotions.first,
                                );
                              } else {
                                // If selectedEmotion is not a CustomEmotion, use the first one
                                dropdownValue = customEmotions.first;
                              }

                              return ThemedCard(
                                child: DropdownButtonFormField<CustomEmotion>(
                                  value: dropdownValue,
                                  items:
                                      customEmotions.map((e) {
                                        final color =
                                            ColorHelper.fromDatabaseColor(
                                              e.color,
                                            );
                                        return DropdownMenuItem(
                                          value: e,
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 16,
                                                height: 16,
                                                margin: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.black12,
                                                  ),
                                                ),
                                              ),
                                              Text(e.name),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      ref.read(emotionProvider.notifier).state =
                                          value;
                                    }
                                  },
                                ),
                              );
                            },
                            loading: () => const CircularProgressIndicator(),
                            error:
                                (e, s) => Column(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Could not load custom emotions',
                                      style: TextStyle(color: Colors.red[700]),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => ref.invalidate(
                                            customEmotionsProvider,
                                          ),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                          )
                        else
                          ThemedCard(
                            child: DropdownButtonFormField<String>(
                              value:
                                  selectedEmotion is String
                                      ? selectedEmotion
                                      : standardEmotions.first.name,
                              items:
                                  standardEmotions.map((e) {
                                    final color = ColorHelper.fromDatabaseColor(
                                      e.color.value,
                                    );
                                    return DropdownMenuItem(
                                      value: e.name,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 16,
                                            height: 16,
                                            margin: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.black12,
                                              ),
                                            ),
                                          ),
                                          Text(e.name),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  ref.read(emotionProvider.notifier).state =
                                      value;
                                }
                              },
                            ),
                          ),
                        const SizedBox(height: 20),
                        const SizedBox(height: 4),
                        PrimaryGradientButton(
                          onPressed: _isSaving ? null : _saveRecord,
                          child:
                              _isSaving
                                  ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                  : const Text('Save record'),
                        ),
                        const SizedBox(height: 16),
                        if (_todaySuggestions.isNotEmpty)
                          ThemedCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Today\'s Suggestions',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                ..._todaySuggestions.map(
                                  (s) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.chevron_right,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text(s)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_todaySuggestions.isNotEmpty)
                          const SizedBox(height: 16),
                        const TokenUsageDisplay(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
