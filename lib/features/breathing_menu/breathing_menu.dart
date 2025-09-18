import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:emotion_ai/data/models/breathing_pattern.dart';
import 'data/breathing_repository.dart';
import '../../shared/providers/app_providers.dart';
import 'create_pattern_dialog.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/gradient_app_bar.dart';
import '../../shared/widgets/themed_card.dart';
import 'package:visibility_detector/visibility_detector.dart';

final breathingRepositoryProvider = Provider<BreathingRepository>((ref) {
  return BreathingRepository(ref.watch(apiServiceProvider));
});

final breathingPatternsProvider = FutureProvider<List<BreathingPattern>>((
  ref,
) async {
  final repo = ref.watch(breathingRepositoryProvider);
  return repo.getPatterns();
});

class BreathingMenuScreen extends ConsumerWidget {
  const BreathingMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patternsAsync = ref.watch(breathingPatternsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'addPatternFab',
        onPressed: () async {
          final newPattern = await showDialog<BreathingPattern>(
            context: context,
            builder: (context) => const CreatePatternDialog(),
          );
          if (newPattern != null) {
            final repo = ref.read(breathingRepositoryProvider);
            await repo.createPattern(newPattern);
            ref.invalidate(breathingPatternsProvider);
          }
        },
        backgroundColor: AppTheme.primaryViolet,
        foregroundColor: Colors.white,
        tooltip: 'Add pattern',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.add),
      ),
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: SafeArea(
          child: Column(
            children: [
              GradientAppBar(title: 'Breathing Menu', actions: const []),
              Expanded(
                child: patternsAsync.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (err, stack) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error: $err',
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed:
                                  () =>
                                      ref.invalidate(breathingPatternsProvider),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                  data: (patterns) {
                    if (patterns.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.air,
                              size: 64,
                              color: AppTheme.primaryViolet.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No breathing patterns yet',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(color: AppTheme.primaryViolet),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create your first pattern to start your breathing journey',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.primaryViolet.withOpacity(0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final newPattern =
                                    await showDialog<BreathingPattern>(
                                      context: context,
                                      builder:
                                          (context) =>
                                              const CreatePatternDialog(),
                                    );
                                if (newPattern != null) {
                                  final repo = ref.read(
                                    breathingRepositoryProvider,
                                  );
                                  await repo.createPattern(newPattern);
                                  ref.invalidate(breathingPatternsProvider);
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Create Pattern'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryViolet,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          // Enforce minimum 2 cards per row (3 on large screens)
                          final int crossAxisCount = width >= 900 ? 3 : 2;
                          // Taller cards on narrow widths to avoid clipping; ensure enough height for title + button
                          final double childAspectRatio =
                              width < 360
                                  ? 0.58
                                  : width < 480
                                  ? 0.70
                                  : 0.90;

                          return GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: childAspectRatio,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                            itemCount: patterns.length,
                            itemBuilder: (context, index) {
                              final pattern = patterns[index];
                              return _BreathingPatternCard(pattern: pattern);
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreathingPatternCard extends StatelessWidget {
  final BreathingPattern pattern;

  const _BreathingPatternCard({required this.pattern});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double baseFont = media.size.width < 380 ? 12 : 14;
    final double titleFont = media.size.width < 380 ? 14 : 16;
    final double chipFont = media.size.width < 380 ? 10 : 12;
    final double padding = media.size.width < 380 ? 12 : 16;
    final colors = [
      AppTheme.primaryViolet,
      AppTheme.primaryPink,
      AppTheme.primaryRed,
      AppTheme.lightViolet,
      AppTheme.lightPink,
      AppTheme.accent,
    ];

    final cardColor = colors[pattern.name.hashCode % colors.length];

    return GestureDetector(
      onTap: () => context.go('/breathing_menu/session', extra: pattern),
      child: ThemedCard(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cardColor.withOpacity(0.1), cardColor.withOpacity(0.05)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardColor.withOpacity(0.3), width: 1),
          ),
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(padding * 0.5),
                      decoration: BoxDecoration(
                        color: cardColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.air,
                        color: cardColor,
                        size: baseFont + 6,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${pattern.cycles}x',
                      style: TextStyle(
                        color: cardColor,
                        fontWeight: FontWeight.bold,
                        fontSize: chipFont,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (context) {
                        final titleStyle = Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cardColor,
                          fontSize: titleFont,
                        );
                        final String cappedTitle =
                            (pattern.name).characters.take(30).toString();
                        final double lineHeight =
                            (titleStyle?.fontSize ?? titleFont) * 1.40;
                        return SizedBox(
                          height: lineHeight,
                          width: double.infinity,
                          child: MarqueeText(
                            text: cappedTitle,
                            style: titleStyle,
                            gap: 32,
                            scrollDuration: const Duration(milliseconds: 20000),
                            pauseDuration: const Duration(milliseconds: 1000),
                            maxLoops: 5,
                          ),
                        );
                      },
                    ),
                    SizedBox(height: padding * 0.35),
                    Row(
                      children: [
                        _BreathingPhaseIndicator(
                          label: 'In',
                          seconds: pattern.inhaleSeconds,
                          color: cardColor,
                        ),
                        const SizedBox(width: 8),
                        _BreathingPhaseIndicator(
                          label: 'Hold',
                          seconds: pattern.holdSeconds,
                          color: cardColor,
                        ),
                        const SizedBox(width: 8),
                        _BreathingPhaseIndicator(
                          label: 'Out',
                          seconds: pattern.exhaleSeconds,
                          color: cardColor,
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: padding * 0.5),
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Tap to start',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cardColor,
                      fontWeight: FontWeight.w600,
                      fontSize: baseFont,
                    ),
                  ),
                ),
                SizedBox(height: padding * 0.5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration scrollDuration;
  final Duration pauseDuration;
  final double gap;
  final int maxLoops;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.scrollDuration = const Duration(milliseconds: 10000),
    this.pauseDuration = const Duration(milliseconds: 1000),
    this.gap = 24,
    this.maxLoops = 5,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _textWidth = 0;
  double _maxWidth = 0;
  bool _isVisible = false;
  int _completedLoops = 0;
  Duration? _appliedDuration;
  late final Key _visibilityKey;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener(_handleStatus);
    _visibilityKey = UniqueKey();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // When the route becomes active again, restart marquee fresh
    _completedLoops = 0;
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateAnimation());
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) async {
    if (status == AnimationStatus.completed) {
      _completedLoops += 1;
      if (_completedLoops >= widget.maxLoops || !_isVisible) {
        _controller.stop();
        return;
      }
      await Future.delayed(widget.pauseDuration);
      if (!mounted) return;
      if (_isVisible) {
        _controller.forward(from: 0);
      }
    }
  }

  void _updateAnimation() {
    if (!mounted) return;
    if (_textWidth <= 0 || _maxWidth <= 0) return;
    final bool overflow = _textWidth > _maxWidth;
    if (!overflow) {
      _controller.stop();
      return;
    }
    final bool routeIsCurrent =
        mounted ? (ModalRoute.of(context)?.isCurrent ?? true) : false;
    if (!routeIsCurrent) {
      _controller.stop();
      _isVisible = false;
      _completedLoops = 0;
      return;
    }
    if (!_isVisible || _completedLoops >= widget.maxLoops) {
      _controller.stop();
      return;
    }
    // Slow speed by using a constant pixels-per-second
    final double travel = _textWidth + widget.gap;
    const double pixelsPerSecond = 30; // slow
    final int durationMs =
        (travel / pixelsPerSecond * 1000).clamp(4000, 40000).toInt();
    final Duration desired = Duration(milliseconds: durationMs);
    if (_appliedDuration != desired) {
      _controller.duration = desired;
      _appliedDuration = desired;
    }
    if (!_controller.isAnimating) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        final bool nowVisible = info.visibleFraction > 0.1;
        if (nowVisible && !_isVisible) {
          _completedLoops = 0; // reset per visible session
        }
        _isVisible = nowVisible;
        if (_isVisible) {
          _updateAnimation();
        } else {
          _controller.stop();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          _maxWidth = constraints.maxWidth;

          // Measure text width
          final textPainter = TextPainter(
            text: TextSpan(text: widget.text, style: widget.style),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout(minWidth: 0, maxWidth: double.infinity);
          _textWidth = textPainter.width;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateAnimation();
          });

          final bool overflow = _textWidth > _maxWidth;

          if (!overflow) {
            return Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          }

          return ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final double travel = _textWidth + widget.gap;
                final double t = _controller.value;
                final double offset = -t * travel;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: _textWidth),
                      child: Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                      ),
                    ),
                    SizedBox(width: widget.gap),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: _textWidth),
                      child: Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BreathingPhaseIndicator extends StatelessWidget {
  final String label;
  final int seconds;
  final Color color;

  const _BreathingPhaseIndicator({
    required this.label,
    required this.seconds,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$seconds',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
