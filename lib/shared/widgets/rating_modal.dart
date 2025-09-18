import 'package:flutter/material.dart';
import 'package:emotion_ai/data/models/breathing_pattern.dart';
import 'package:emotion_ai/data/models/breathing_session.dart';

class RatingModal extends StatefulWidget {
  final BreathingPattern pattern;
  final void Function(BreathingSessionData session) onSave;
  final VoidCallback onCancel;

  const RatingModal({
    super.key,
    required this.pattern,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<RatingModal> createState() => _RatingModalState();
}

class _RatingModalState extends State<RatingModal> {
  double _rating = 3.0; // backend expects 1..5
  final TextEditingController _commentController = TextEditingController();
  String? _errorMsg;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Rate Your Session"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Slider(
            value: _rating,
            min: 1,
            max: 5,
            divisions: 4,
            label: _rating.toStringAsFixed(0),
            onChanged: (value) {
              setState(() {
                _rating = value;
              });
            },
          ),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              labelText: "Add a comment",
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _commentController.clear();
            widget.onCancel();
          },
          child: const Text("Don't Save"),
        ),
        ElevatedButton(
          onPressed: () {
            final session = BreathingSessionData(
              pattern: widget.pattern.name,
              rating: _rating.toDouble(),
              comment: _commentController.text.trim(),
              createdAt: DateTime.now(),
            );
            try {
              widget.onSave(session);
            } catch (e) {
              setState(() => _errorMsg = 'Failed to save: $e');
            }
          },
          child: const Text("Save Meditation"),
        ),
      ],
    );
  }
}
