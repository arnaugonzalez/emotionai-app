import 'dart:convert';

Map<String, dynamic>? _tryDecodeJson(String raw) {
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

String _encodeJson(Map<String, dynamic> data) => jsonEncode(data);

class EmotionalRecord {
  final String? id;
  final String source;
  final String description;
  final String emotion;
  final int color;
  final String? customEmotionName;
  final int? customEmotionColor;
  final DateTime createdAt;

  // Enhanced backend-aligned fields
  final int intensity; // 1-10 scale
  final List<String> triggers;
  final String? notes;
  final Map<String, dynamic>? contextData;
  final List<String> tags;
  final double? tagConfidence;
  final bool processedForTags;
  final DateTime? recordedAt;

  EmotionalRecord({
    this.id,
    required this.source,
    required this.description,
    required this.emotion,
    required this.color,
    this.customEmotionName,
    this.customEmotionColor,
    required this.createdAt,
    this.intensity = 5,
    this.triggers = const [],
    this.notes,
    this.contextData,
    this.tags = const [],
    this.tagConfidence,
    this.processedForTags = false,
    this.recordedAt,
  });

  factory EmotionalRecord.fromJson(Map<String, dynamic> json) {
    return EmotionalRecord(
      id: json['id']?.toString(), // Ensure string conversion
      source: json['source'] ?? '',
      description: json['description'] ?? '',
      emotion: json['emotion'] ?? '',
      color:
          json['color'] is int
              ? json['color']
              : int.tryParse(json['color']?.toString() ?? '0') ?? 0,
      customEmotionName: json['custom_emotion_name'],
      customEmotionColor: json['custom_emotion_color'],
      createdAt: DateTime.parse(json['created_at']),
      intensity: json['intensity'] ?? 5,
      triggers: List<String>.from(json['triggers'] ?? []),
      notes: json['notes'],
      contextData: json['context_data'],
      tags: List<String>.from(json['tags'] ?? []),
      tagConfidence: json['tag_confidence']?.toDouble(),
      processedForTags: json['processed_for_tags'] ?? false,
      recordedAt:
          json['recorded_at'] != null
              ? DateTime.parse(json['recorded_at'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'source': source,
      'description': description,
      'emotion': emotion,
      'color': color,
      'custom_emotion_name': customEmotionName,
      'custom_emotion_color': customEmotionColor,
      'intensity': intensity,
      'triggers': triggers,
      'notes': notes,
      'context_data': contextData,
      'tags': tags,
      'tag_confidence': tagConfidence,
      'processed_for_tags': processedForTags,
      'recorded_at': recordedAt?.toIso8601String(),
    };
  }

  // SQLite methods
  factory EmotionalRecord.fromMap(Map<String, dynamic> map) {
    return EmotionalRecord(
      id: map['id']?.toString(),
      source: map['source'] ?? '',
      description: map['description'] ?? '',
      emotion: map['emotion'] ?? '',
      color: int.tryParse(map['color'].toString()) ?? 0,
      customEmotionName: map['customEmotionName'],
      customEmotionColor: map['customEmotionColor'],
      createdAt: DateTime.parse(
        map['date'] ?? DateTime.now().toIso8601String(),
      ),
      intensity: map['intensity'] ?? 5,
      triggers:
          map['triggers'] is String
              ? (map['triggers'] as String).split(',').where((s) => s.isNotEmpty).toList()
              : <String>[],
      notes: map['notes'],
      contextData:
          map['contextData'] is String
              ? (Map<String, dynamic>.from(
                  _tryDecodeJson(map['contextData'] as String) ?? {}))
              : (map['contextData'] != null
                  ? Map<String, dynamic>.from(map['contextData'])
                  : null),
      tags:
          map['tags'] is String
              ? (map['tags'] as String).split(',').where((s) => s.isNotEmpty).toList()
              : <String>[],
      tagConfidence: map['tagConfidence']?.toDouble(),
      processedForTags: map['processedForTags'] == 1,
      recordedAt:
          map['recordedAt'] != null ? DateTime.parse(map['recordedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': createdAt.toIso8601String(),
      'source': source,
      'description': description,
      'emotion': emotion,
      'color': color.toString(),
      'customEmotionName': customEmotionName,
      'customEmotionColor': customEmotionColor,
      'intensity': intensity,
      'triggers': triggers.join(','),
      'notes': notes,
      'contextData': contextData != null ? _encodeJson(contextData!) : null,
      'tags': tags.join(','),
      'tagConfidence': tagConfidence,
      'processedForTags': processedForTags ? 1 : 0,
      'recordedAt':
          recordedAt?.toIso8601String() ?? createdAt.toIso8601String(),
      'synced': 0,
    };
  }

  // Helper method to copy with new values
  EmotionalRecord copyWith({
    String? id,
    String? source,
    String? description,
    String? emotion,
    int? color,
    String? customEmotionName,
    int? customEmotionColor,
    DateTime? createdAt,
    int? intensity,
    List<String>? triggers,
    String? notes,
    Map<String, dynamic>? contextData,
    List<String>? tags,
    double? tagConfidence,
    bool? processedForTags,
    DateTime? recordedAt,
  }) {
    return EmotionalRecord(
      id: id ?? this.id,
      source: source ?? this.source,
      description: description ?? this.description,
      emotion: emotion ?? this.emotion,
      color: color ?? this.color,
      customEmotionName: customEmotionName ?? this.customEmotionName,
      customEmotionColor: customEmotionColor ?? this.customEmotionColor,
      createdAt: createdAt ?? this.createdAt,
      intensity: intensity ?? this.intensity,
      triggers: triggers ?? this.triggers,
      notes: notes ?? this.notes,
      contextData: contextData ?? this.contextData,
      tags: tags ?? this.tags,
      tagConfidence: tagConfidence ?? this.tagConfidence,
      processedForTags: processedForTags ?? this.processedForTags,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }
}
