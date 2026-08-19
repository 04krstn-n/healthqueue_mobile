/// Chat message model — field names match chatbot_screen + app_state usage
class ChatMessage {
  final String        id;
  final String        text;           // message content
  final bool          isUser;         // true = patient, false = bot
  final DateTime      timestamp;
  final List<String>  quickReplies;

  const ChatMessage({
    String?       id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.quickReplies = const [],
  }) : id = id ?? '';
}

/// Keep ChatSender for any legacy references
enum ChatSender { bot, user }
