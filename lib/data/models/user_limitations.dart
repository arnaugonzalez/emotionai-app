class UserLimitations {
  final int dailyTokenLimit;
  final int dailyTokensUsed;
  final bool isUnlimited;
  final bool canMakeRequest;
  final String? limitMessage;
  final DateTime? limitResetTime;
  final double dailyCostLimit;
  final double dailyCostUsed;
  final double monthlyCost;
  final int todayTokensUsed;

  UserLimitations({
    required this.dailyTokenLimit,
    required this.dailyTokensUsed,
    required this.isUnlimited,
    required this.canMakeRequest,
    this.limitMessage,
    this.limitResetTime,
    required this.dailyCostLimit,
    required this.dailyCostUsed,
    this.monthlyCost = 0.0,
    this.todayTokensUsed = 0,
  });

  factory UserLimitations.fromJson(Map<String, dynamic> json) {
    return UserLimitations(
      dailyTokenLimit: json['daily_token_limit'] ?? 0,
      dailyTokensUsed: json['daily_tokens_used'] ?? 0,
      isUnlimited: json['is_unlimited'] ?? false,
      canMakeRequest: json['can_make_request'] ?? false,
      limitMessage: json['limit_message'],
      limitResetTime:
          json['limit_reset_time'] != null
              ? DateTime.parse(json['limit_reset_time'])
              : null,
      dailyCostLimit: (json['daily_cost_limit'] ?? 0.0).toDouble(),
      dailyCostUsed: (json['daily_cost_used'] ?? 0.0).toDouble(),
      monthlyCost: (json['monthly_cost'] ?? 0.0).toDouble(),
      todayTokensUsed:
          json['daily_tokens_used'] ?? json['today_tokens_used'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'daily_token_limit': dailyTokenLimit,
      'daily_tokens_used': dailyTokensUsed,
      'is_unlimited': isUnlimited,
      'can_make_request': canMakeRequest,
      'limit_message': limitMessage,
      'limit_reset_time': limitResetTime?.toIso8601String(),
      'daily_cost_limit': dailyCostLimit,
      'daily_cost_used': dailyCostUsed,
      'monthly_cost': monthlyCost,
      'today_tokens_used': todayTokensUsed,
    };
  }

  int get remainingTokens =>
      isUnlimited ? -1 : (dailyTokenLimit - dailyTokensUsed);

  double get remainingCost => dailyCostLimit - dailyCostUsed;

  double get usagePercentage =>
      isUnlimited
          ? 0.0
          : (dailyTokensUsed / dailyTokenLimit * 100).clamp(0.0, 100.0);

  double get costPercentage =>
      (dailyCostUsed / dailyCostLimit * 100).clamp(0.0, 100.0);
}
