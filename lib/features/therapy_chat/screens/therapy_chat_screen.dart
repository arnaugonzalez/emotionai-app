import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/therapy_chat_provider.dart';
import '../widgets/chat_message_widget.dart';
import '../widgets/agent_selector.dart';
import '../../usage/providers/user_limitations_provider.dart';
import 'package:intl/intl.dart';
import 'package:emotion_ai/core/theme/app_theme.dart';
import 'package:flutter/foundation.dart';

class TherapyChatScreen extends ConsumerStatefulWidget {
  const TherapyChatScreen({super.key});

  @override
  ConsumerState<TherapyChatScreen> createState() => _TherapyChatScreenState();
}

class _TherapyChatScreenState extends ConsumerState<TherapyChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      // Check if user can make requests from backend limitations
      final canMakeRequest = ref.read(canMakeRequestProvider);

      if (!canMakeRequest) {
        _showTokenLimitDialog();
        return;
      }

      ref.read(therapyChatProvider.notifier).sendMessage(text);
      _messageController.clear();
      _scrollToBottom();
    }
  }

  void _showTokenLimitDialog() {
    final limitations = ref.read(limitationsDataProvider);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Usage Limit Reached'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  limitations?.limitMessage ??
                      'You have reached your daily usage limit. This helps us ensure fair usage of the AI service for all users.',
                ),
                if (limitations?.limitResetTime != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Your limit will reset at ${DateFormat.jm().format(limitations!.limitResetTime!)} on ${DateFormat.yMMMd().format(limitations.limitResetTime!)}.',
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Need a higher limit? Please contact support for more information.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/profile');
                },
                child: const Text('View Usage Stats'),
              ),
            ],
          ),
    );
  }

  Widget _buildCrisisBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.red.shade700,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crisis Support Available',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'If you are in immediate danger, please contact emergency services. '
                  'You are not alone.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () =>
                ref.read(therapyChatProvider.notifier).dismissCrisis(),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Conversation History'),
            content: const Text(
              'This will delete your entire conversation history with the AI assistant. This action cannot be undone. Do you want to continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  ref
                      .read(therapyChatProvider.notifier)
                      .clearConversationHistory();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Conversation history cleared'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Clear'),
              ),
            ],
          ),
    );
  }

  void _showAgentSelector() {
    final currentAgent = ref.read(therapyChatProvider).selectedAgent;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Switch AI Assistant'),
            content: SingleChildScrollView(
              child: AgentSelector(
                selectedAgent: currentAgent,
                onAgentChanged: (agentType) {
                  ref.read(therapyChatProvider.notifier).changeAgent(agentType);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Switched to ${agentType == 'therapy' ? 'Therapy' : 'Wellness'} Assistant',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(therapyChatProvider);
    final limitations = ref.watch(limitationsDataProvider);
    final canMakeRequest = limitations?.canMakeRequest ?? true;

    // Debug information
    print(
      'TherapyChatScreen: Building with chatState: ${chatState.messages.length} messages',
    );
    print('TherapyChatScreen: isLoading: ${chatState.isLoading}');
    print('TherapyChatScreen: error: ${chatState.error}');
    print('TherapyChatScreen: selectedAgent: ${chatState.selectedAgent}');

    // Safely scroll to bottom when messages are added
    if (chatState.messages.isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          try {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          } catch (e) {
            print('Error scrolling to bottom: $e');
          }
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Talk it Through'),
        backgroundColor: AppTheme.primaryViolet,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              chatState.selectedAgent == 'therapy'
                  ? Icons.psychology
                  : Icons.spa,
            ),
            tooltip: 'Switch AI Assistant',
            onPressed: () => _showAgentSelector(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear conversation history',
            onPressed: () => _showClearHistoryDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Crisis banner — shown above everything else when crisis detected
          if (chatState.crisisDetected) _buildCrisisBanner(),

          // Backend limitations warning
          if (!canMakeRequest && limitations?.limitMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      limitations!.limitMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: _showTokenLimitDialog,
                    child: const Text('Learn More'),
                  ),
                ],
              ),
            ),

          // Debug info (temporary)
          if (kDebugMode)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.yellow.withOpacity(0.3),
              child: Text(
                'Debug: ${chatState.messages.length} messages, Agent: ${chatState.selectedAgent}',
                style: const TextStyle(fontSize: 12),
              ),
            ),

          // Chat messages
          Expanded(
            child:
                chatState.messages.isEmpty
                    ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Your conversation will appear here',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Start by typing a message below',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: chatState.messages.length,
                      itemBuilder: (context, index) {
                        final message = chatState.messages[index];
                        return ChatMessageWidget(message: message);
                      },
                    ),
          ),

          // Loading indicator
          if (chatState.isLoading)
            Container(
              padding: const EdgeInsets.all(8.0),
              child: const LinearProgressIndicator(),
            ),

          // Error message
          if (chatState.error != null)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.red.withAlpha(30),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chatState.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      ref.read(therapyChatProvider.notifier).clearError();
                    },
                  ),
                ],
              ),
            ),

          // Message input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: canMakeRequest && !chatState.isLoading,
                    decoration: InputDecoration(
                      hintText:
                          !canMakeRequest
                              ? 'Usage limit reached'
                              : 'Type your message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => !canMakeRequest ? null : _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed:
                      (!canMakeRequest || chatState.isLoading)
                          ? null
                          : _sendMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryViolet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
