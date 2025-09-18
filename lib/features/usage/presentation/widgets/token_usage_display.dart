import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../usage/providers/user_limitations_provider.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class TokenUsageDisplay extends ConsumerWidget {
  const TokenUsageDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limitationsState = ref.watch(userLimitationsProvider);

    if (limitationsState.isLoading) {
      return const SizedBox(
        height: 50,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (limitationsState.error != null) {
      return SizedBox(
        height: 50,
        child: Center(
          child: Text(
            limitationsState.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    if (limitationsState.limitations == null) {
      return const SizedBox(
        height: 50,
        child: Center(child: Text('No usage data available')),
      );
    }

    final limitations = limitationsState.limitations!;
    final usagePercentage = limitations.usagePercentage;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily API Usage',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tokens Used Today',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    limitations.isUnlimited
                        ? '${limitations.dailyTokensUsed} / Unlimited'
                        : '${limitations.dailyTokensUsed} / ${limitations.dailyTokenLimit}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Cost Today',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '€${limitations.dailyCostUsed.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Monthly cost just below the header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monthly Cost',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '€${(limitations.monthlyCost).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!limitations.isUnlimited) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: usagePercentage / 100,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                color:
                    usagePercentage > 90
                        ? Theme.of(context).colorScheme.error
                        : usagePercentage > 75
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.primary,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${usagePercentage.toStringAsFixed(1)}% used',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${limitations.remainingTokens} remaining',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
          if (limitations.limitMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    limitations.canMakeRequest
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    limitations.canMakeRequest
                        ? Icons.info_outline
                        : Icons.warning_outlined,
                    size: 16,
                    color:
                        limitations.canMakeRequest
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      limitations.limitMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            limitations.canMakeRequest
                                ? Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer
                                : Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (limitations.limitResetTime != null) ...[
            const SizedBox(height: 8),
            Text(
              'Resets: ${DateFormat.jm().format(limitations.limitResetTime!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
