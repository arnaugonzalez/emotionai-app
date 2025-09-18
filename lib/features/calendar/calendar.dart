import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emotion_ai/utils/color_utils.dart';
import './events/offline_calendar_provider.dart';

import 'package:table_calendar/table_calendar.dart';
import 'package:logger/logger.dart';
import 'package:emotion_ai/core/theme/app_theme.dart';
import 'package:emotion_ai/shared/widgets/gradient_app_bar.dart';
import 'package:emotion_ai/shared/widgets/themed_card.dart';
import 'package:emotion_ai/shared/widgets/primary_gradient_button.dart';

final logger = Logger();

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isLoadingPresets = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;

    Future.microtask(() {
      if (!mounted) return;
      ref.read(offlineCalendarProvider.notifier).fetchEvents();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fallback fetch when screen appears or dependencies change
    Future.microtask(() {
      if (!mounted) return;
      ref.read(offlineCalendarProvider.notifier).fetchEvents();
    });
  }

  Future<void> _loadPresetData() async {
    if (!mounted) return;

    setState(() {
      _isLoadingPresets = true;
    });

    try {
      // Use provider method which prefers backend dev seed and falls back to local
      await ref.read(offlineCalendarProvider.notifier).addPresetData();
      if (!mounted) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preset data loaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      logger.e('Error loading preset data: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load preset data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPresets = false;
        });
      }
    }
  }

  List<Widget> _buildEventMarkers(
    DateTime day,
    Map<DateTime, List<dynamic>> emotionalEvents,
    Map<DateTime, List<dynamic>> breathingEvents,
  ) {
    // Normalize date to compare just year, month, and day
    final normalizedDay = DateTime(day.year, day.month, day.day);

    // Find matching events
    final emotionalRecords =
        emotionalEvents.entries
            .where(
              (entry) =>
                  entry.key.year == normalizedDay.year &&
                  entry.key.month == normalizedDay.month &&
                  entry.key.day == normalizedDay.day,
            )
            .expand((entry) => entry.value)
            .toList();

    final breathingSessions =
        breathingEvents.entries
            .where(
              (entry) =>
                  entry.key.year == normalizedDay.year &&
                  entry.key.month == normalizedDay.month &&
                  entry.key.day == normalizedDay.day,
            )
            .expand((entry) => entry.value)
            .toList();

    // Limit the number of markers to prevent overflow
    const maxMarkers = 3;
    final totalEvents = emotionalRecords.length + breathingSessions.length;

    if (totalEvents == 0) return [];

    if (totalEvents <= maxMarkers) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Wrap(
            spacing: 3,
            children: [
              ...emotionalRecords.map((record) {
                final raw = record.customEmotionColor ?? record.color;
                return Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: ColorHelper.fromDatabaseColor(raw),
                    shape: BoxShape.circle,
                  ),
                );
              }),
              ...breathingSessions.map(
                (_) => Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blueAccent, width: 1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    } else {
      // Show a counter instead when there are too many events
      return [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '+$totalEvents',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
      ];
    }
  }

  // Error display helper methods
  IconData _getErrorIcon(String? errorMessage) {
    final message = errorMessage?.toLowerCase() ?? '';
    if (message.contains('timeout') || message.contains('connection')) {
      return Icons.wifi_off;
    } else if (message.contains('type') || message.contains('subtype')) {
      return Icons.warning;
    } else {
      return Icons.error_outline;
    }
  }

  Color _getErrorColor(String? errorMessage) {
    final message = errorMessage?.toLowerCase() ?? '';
    if (message.contains('timeout') || message.contains('connection')) {
      return Colors.orange;
    } else if (message.contains('type') || message.contains('subtype')) {
      return Colors.amber;
    } else {
      return Colors.red;
    }
  }

  String _getErrorTitle(String? errorMessage) {
    final message = errorMessage?.toLowerCase() ?? '';
    if (message.contains('timeout') || message.contains('connection')) {
      return 'Connection Problem';
    } else if (message.contains('type') || message.contains('subtype')) {
      return 'Data Format Issue';
    } else {
      return 'Something Went Wrong';
    }
  }

  String _getErrorDescription(String? errorMessage) {
    final message = errorMessage?.toLowerCase() ?? '';
    if (message.contains('timeout') || message.contains('connection')) {
      return 'Unable to connect to the server. Please check your internet connection and try again.';
    } else if (message.contains('type') || message.contains('subtype')) {
      return 'The data format is not compatible. This issue has been logged and app defaults will be used.';
    } else {
      return 'An unexpected error occurred while loading calendar data. Please try again.';
    }
  }

  bool _shouldShowTechnicalDetails(String? errorMessage) {
    final message = errorMessage?.toLowerCase() ?? '';
    return message.contains('type') ||
        message.contains('subtype') ||
        message.contains('validation');
  }

  List<Widget> _buildDetailsForSelectedDay(
    DateTime day,
    Map<DateTime, List<dynamic>> emotionalEvents,
    Map<DateTime, List<dynamic>> breathingEvents,
  ) {
    // Normalize date to compare just year, month, and day
    final normalizedDay = DateTime(day.year, day.month, day.day);

    // Find matching events
    final emotionalRecords =
        emotionalEvents.entries
            .where(
              (entry) =>
                  entry.key.year == normalizedDay.year &&
                  entry.key.month == normalizedDay.month &&
                  entry.key.day == normalizedDay.day,
            )
            .expand((entry) => entry.value)
            .toList();

    final breathingSessions =
        breathingEvents.entries
            .where(
              (entry) =>
                  entry.key.year == normalizedDay.year &&
                  entry.key.month == normalizedDay.month &&
                  entry.key.day == normalizedDay.day,
            )
            .expand((entry) => entry.value)
            .toList();

    if (emotionalRecords.isEmpty && breathingSessions.isEmpty) {
      return [const ListTile(title: Text('No events for this day'))];
    }

    return [
      if (emotionalRecords.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8.0, left: 16.0, bottom: 4.0),
          child: Text(
            'Emotional Records',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ...emotionalRecords.map(
        (record) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: ColorHelper.fromDatabaseColor(
                record.customEmotionColor ?? record.color,
              ),
              radius: 16,
            ),
            title: Text(
              record.customEmotionName?.toUpperCase() ??
                  record.emotion.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.description),
                Text(
                  'Source: ${record.source}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      if (breathingSessions.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16.0, left: 16.0, bottom: 4.0),
          child: Text(
            'Breathing Sessions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ...breathingSessions.map(
        (session) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.blue,
              radius: 16,
              child: Icon(Icons.air, color: Colors.white, size: 18),
            ),
            title: Text('Pattern: ${session.pattern}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rating: ${session.rating}/5'),
                if (session.comment != null && session.comment!.isNotEmpty)
                  Text('Comment: ${session.comment!}'),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final calendarState = ref.watch(offlineCalendarProvider);

    if (calendarState.state == CalendarLoadState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (calendarState.state == CalendarLoadState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getErrorIcon(calendarState.errorMessage),
                size: 64,
                color: _getErrorColor(calendarState.errorMessage),
              ),
              const SizedBox(height: 16),
              Text(
                _getErrorTitle(calendarState.errorMessage),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _getErrorColor(calendarState.errorMessage),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _getErrorDescription(calendarState.errorMessage),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed:
                    () =>
                        ref
                            .read(offlineCalendarProvider.notifier)
                            .fetchEvents(),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
              if (_shouldShowTechnicalDetails(calendarState.errorMessage)) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('Technical Details'),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        calendarState.errorMessage ?? 'Unknown error',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          children: [
            const SizedBox(height: 8),
            const GradientAppBar(title: 'Calendar'),
            const SizedBox(height: 8),
            ThemedCard(
              child: PrimaryGradientButton(
                onPressed: _isLoadingPresets ? null : _loadPresetData,
                child:
                    _isLoadingPresets
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text('Load Test Data'),
              ),
            ),
            const SizedBox(height: 8),
            ThemedCard(
              padding: const EdgeInsets.all(8),
              child: TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                calendarStyle: const CalendarStyle(
                  markersMaxCount: 3,
                  markerSize: 6,
                  markerMargin: EdgeInsets.symmetric(horizontal: 0.5),
                ),
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _buildEventMarkers(
                        day,
                        calendarState.emotionalEvents,
                        calendarState.breathingEvents,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ThemedCard(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView(
                  children: _buildDetailsForSelectedDay(
                    _selectedDay ?? _focusedDay,
                    calendarState.emotionalEvents,
                    calendarState.breathingEvents,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
