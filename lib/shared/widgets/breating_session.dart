import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:emotion_ai/shared/widgets/rating_modal.dart';
import 'dart:async';
import 'package:emotion_ai/data/models/breathing_pattern.dart';
import 'package:emotion_ai/features/auth/auth_provider.dart';

class BreathingSessionScreen extends ConsumerStatefulWidget {
  final BreathingPattern pattern;
  const BreathingSessionScreen({super.key, required this.pattern});

  @override
  ConsumerState<BreathingSessionScreen> createState() =>
      _BreathingSessionScreenState();
}

class _BreathingSessionScreenState extends ConsumerState<BreathingSessionScreen>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _timer;
  String _phase = "Inhale";
  int _phaseIndex = 0;
  int _currentCycle = 1;
  List<int> _phases = [];
  bool _sessionCompleted = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _phases = [
      widget.pattern.inhaleSeconds,
      widget.pattern.holdSeconds,
      widget.pattern.exhaleSeconds,
      widget.pattern.restSeconds,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _startPhase();
      }
    });
  }

  void _startPhase() {
    if (_isDisposed) return;

    if (_phaseIndex == 0 && _currentCycle > widget.pattern.cycles) {
      setState(() {
        _sessionCompleted = true;
      });
      _showRatingModal();
      return;
    }

    // Dispose of previous controller if exists
    _controller?.dispose();

    final duration = Duration(seconds: _phases[_phaseIndex]);
    _phase = ["Inhale", "Hold", "Exhale", "Rest"][_phaseIndex];

    // Create new controller
    _controller = AnimationController(vsync: this, duration: duration)
      ..addListener(() {
        if (!_isDisposed && mounted) {
          setState(() {});
        }
      });

    if (!_isDisposed) {
      _controller!.forward();

      // Cancel previous timer if exists
      _timer?.cancel();
      _timer = Timer(duration, _nextPhase);
    }
  }

  void _nextPhase() {
    if (_isDisposed || !mounted) return;

    // Check for null before disposing
    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
    }

    setState(() {
      if (_phaseIndex == _phases.length - 1) {
        _currentCycle++;
        _phaseIndex = 0;
      } else {
        _phaseIndex++;
      }
    });

    if (!_isDisposed) {
      _startPhase();
    }
  }

  void _showRatingModal() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return RatingModal(
          pattern: widget.pattern,
          onSave: (session) async {
            final apiService = ref.read(apiServiceProvider);
            await apiService.createBreathingSession(session);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Session saved successfully')),
              );
              context.pop();
              context.pop();
            }
          },
          onCancel: () {
            if (!context.mounted) return;
            context.pop(); // Close the modal
            context.pop(); // Return to breathing menu
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondsLeft =
        (_controller?.duration?.inSeconds ?? 0) -
        ((_controller?.value ?? 0.0) * (_controller?.duration?.inSeconds ?? 0))
            .round();
    final isInhale = _phase == "Inhale";
    return Scaffold(
      appBar: AppBar(title: const Text("Breathing Session")),
      body: SafeArea(
        child: Center(
          child:
              _sessionCompleted
                  ? const Text("Session Completed!")
                  : LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest.shortestSide * 0.6;
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _phase,
                              style: Theme.of(
                                context,
                              ).textTheme.headlineLarge?.copyWith(
                                fontWeight:
                                    isInhale
                                        ? FontWeight.bold
                                        : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                CustomPaint(
                                  size: Size(size, size),
                                  painter: CircleBreathPainter(
                                    value: _controller?.value ?? 0.0,
                                    inhale: isInhale,
                                  ),
                                ),
                                Text(
                                  '$secondsLeft',
                                  style:
                                      Theme.of(
                                        context,
                                      ).textTheme.headlineMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Cycle $_currentCycle of ${widget.pattern.cycles}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                _timer?.cancel();
                                setState(() {
                                  _sessionCompleted = true;
                                });
                                _showRatingModal();
                              },
                              child: const Text("Stop Session"),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ),
    );
  }
}

class CircleBreathPainter extends CustomPainter {
  final double value;
  final bool inhale;

  CircleBreathPainter({required this.value, required this.inhale});

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = Colors.blueAccent;
    final alpha =
        (inhale ? (155 + (100 * value)) : (255 * (1 - value)))
            .clamp(50, 255)
            .toInt();
    final paint =
        Paint()
          ..color = baseColor.withAlpha(alpha)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;

    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;
    final currentRadius = maxRadius * value;

    canvas.drawCircle(center, currentRadius, paint);
  }

  @override
  bool shouldRepaint(CircleBreathPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.inhale != inhale;
  }
}
