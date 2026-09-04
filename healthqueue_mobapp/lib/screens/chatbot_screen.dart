import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../state/app_state.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';

class ChatbotScreen extends StatefulWidget {
  final VoidCallback onBookAppointment;
  final VoidCallback onViewQueue;
  const ChatbotScreen({super.key, required this.onBookAppointment,
      required this.onViewQueue});
  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _escalated = false;
  bool _sending   = false;
  String? _lastLogId;

  // A clinic the patient explicitly picked from the chat (separate from
  // whatever clinic they may already have via an active queue/appointment).
  // Lets escalation reach staff even when the patient hasn't joined a
  // queue or booked an appointment yet.
  String? _selectedClinicId;
  String? _selectedClinicName;

  // ── Quick reply chips ─────────────────────────────────────────────────────
  // These MUST exactly match or be contained by the local-handler conditions below
  static const _quickReplies = [
    'Check my queue status',
    'Join the queue',
    'Book an appointment',
    'Find clinic near me',
    'Estimated wait time',
    'Select clinic',
    'Talk to staff',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Loads the last 7 days of conversation from the server (falls back
      // to the normal greeting if there's no history yet or it can't be
      // reached) instead of always starting from a blank slate.
      await context.read<AppState>().loadChatHistory();
      if (!mounted) return;
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Best clinic name we currently know about: an explicit pick from this
  // chat session takes priority, then whatever clinic the patient already
  // has via an active queue or upcoming appointment.
  String? _effectiveClinicName(AppState appState) {
    if (_selectedClinicName != null) return _selectedClinicName;
    if (appState.currentQueue != null) return appState.currentQueue!.clinicName;
    if (appState.upcomingAppointments.isNotEmpty) {
      final name = appState.upcomingAppointments.first.clinicName;
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  // Lets the patient explicitly choose which clinic their question/escalation
  // should go to, instead of only relying on an active queue or appointment.
  Future<void> _pickClinic() async {
    List<dynamic> clinics = [];
    try {
      clinics = await ApiService.getClinicDirectory();
    } catch (_) {}
    if (!mounted) return;
    if (clinics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not load the clinic list. Check your connection and try again.'),
      ));
      return;
    }

    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClinicPickerSheet(clinics: clinics),
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedClinicId = selected['id'];
        _selectedClinicName = selected['name'];
      });
    }
  }

  // Handles a "talk to staff" request end-to-end: resolves (or asks for) a
  // clinic, sends the escalation, and always leaves a clear, visible
  // confirmation message in the chat feed — not just the small header badge,
  // which is easy to miss.
  Future<void> _escalateToStaff(AppState appState, {required String note}) async {
    String? clinicId = _selectedClinicId;
    String? clinicName = _effectiveClinicName(appState);

    // Nothing to go on at all — ask the patient to pick a clinic right here
    // instead of just telling them to go join a queue first.
    if (clinicId == null && !appState.hasSelectedClinic) {
      appState.addBotText(
        "I'd like to connect you with staff, but I don't know which clinic to alert yet. "
        "Please pick a clinic below, or join a queue / book an appointment first.",
      );
      await _pickClinic();
      if (_selectedClinicId == null) return; // patient dismissed the picker
      clinicId = _selectedClinicId;
      clinicName = _selectedClinicName;
    }

    appState.addBotText(
      "Connecting you with staff${clinicName != null ? ' at $clinicName' : ''}. One moment…",
    );

    final result = await ApiService.escalateChatbot(
      logId: _lastLogId,
      note: note,
      clinicId: clinicId,
    );

    if (result.ok) {
      setState(() => _escalated = true);
      appState.addBotText(
        "✅ Staff${clinicName != null ? ' at $clinicName' : ''} have been notified of your request "
        "and will follow up shortly. The \"Staff notified\" badge above will stay on while it's pending.",
      );
    } else if (result.requiresClinic) {
      appState.addBotText(
        result.message ?? 'Please select a clinic before requesting staff assistance.',
      );
      await _pickClinic();
      if (_selectedClinicId != null && mounted) {
        await _escalateToStaff(appState, note: note); // retry once with the picked clinic
      }
    } else {
      appState.addBotText(
        "I couldn't reach staff just now. Please try again in a moment, or visit the clinic "
        "reception desk directly for anything urgent.",
      );
    }
  }

  // ── Local intent matching — handles common phrases WITHOUT hitting server ──
  Future<bool> _handleLocally(String msg, AppState appState) async {
    final l = msg.toLowerCase();

    // 1. Queue status check
    if (l.contains('queue status') || l.contains('check my queue') ||
        l.contains('my queue') || l == 'queue') {
      final qs = appState.currentQueueStatus;
      if (qs.inQueue) {
        final e = qs.entry!;
        appState.addBotText(
          'You\'re in the queue at ${e.clinicName}.\n'
          'Queue #${e.queueNumber} · Position: ${qs.position} · '
          'Est. wait: ~${qs.estimatedWaitTime} min.',
          quickReplies: ['View queue details', 'Cancel my queue'],
        );
      } else {
        appState.addBotText(
          "You're not in any queue right now. Would you like to join one?",
          quickReplies: ['Join the queue', 'Find clinic near me'],
        );
      }
      return true;
    }

    // 2. Join queue
    if (l.contains('join') || l.contains('get a number') ||
        l.contains('queue number') || l.contains('get in line') ||
        l.contains('join queue') || l.contains('join the queue') ||
        l == 'queue me' || l == 'pila') {
      appState.addBotText(
        'To join the queue, tap the Queue tab at the bottom of the screen, '
        'or use the "Get Queue Number" button on the dashboard. '
        'You\'ll choose your clinic and service, then get your queue number instantly.',
        quickReplies: ['Check my queue status', 'Find clinic near me'],
      );
      // Also navigate to queue tab after short delay
      setState(() => _sending = false);
      _scrollToBottom();
      return true;
    }

    // 3. Book appointment
    if (l.contains('book') || l.contains('appointment') ||
        l.contains('schedule') || l.contains('reserve')) {
      appState.addBotText(
        "I'll take you to the booking screen now. 📅",
        quickReplies: ['Check my queue status', 'Find clinic near me'],
      );
      setState(() => _sending = false);
      _scrollToBottom();
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) widget.onBookAppointment();
      return true;
    }

    // 4. Find clinic / map
    if (l.contains('find clinic') || l.contains('near me') ||
        l.contains('nearest') || l.contains('map') ||
        l.contains('clinic location') || l.contains('saan')) {
      appState.addBotText(
        "Opening the clinic map. Clinics are ranked by wait time and distance. 📍",
        quickReplies: ['Join the queue', 'Book an appointment'],
      );
      setState(() => _sending = false);
      _scrollToBottom();
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.pushNamed(context, AppRoutes.clinicMap);
      return true;
    }

    // 5. Estimated wait time
    if (l.contains('wait') || l.contains('how long') ||
        l.contains('eta') || l.contains('estimated')) {
      final qs = appState.currentQueueStatus;
      if (qs.inQueue) {
        appState.addBotText(
          'Your estimated wait time is ~${qs.estimatedWaitTime} minutes '
          '(${(qs.position - 1).clamp(0, 999)} ahead of you).',
          quickReplies: ['Check my queue status', 'Talk to staff'],
        );
      } else {
        appState.addBotText(
          "Wait times vary by clinic and time of day. Check the clinic map "
          "for live wait times near you — clinics are ranked by shortest wait. ⏱",
          quickReplies: ['Find clinic near me', 'Join the queue'],
        );
      }
      return true;
    }

    // 6. Cancel queue
    if (l.contains('cancel') && l.contains('queue')) {
      final qs = appState.currentQueueStatus;
      if (qs.inQueue) {
        appState.addBotText(
          'To cancel your queue, go to the Queue tab and tap "Leave Queue".',
          quickReplies: ['View queue details', 'Talk to staff'],
        );
      } else {
        appState.addBotText(
          "You're not in any active queue right now.",
          quickReplies: ['Join the queue', 'Check my queue status'],
        );
      }
      return true;
    }

    // 7. View queue details
    if (l.contains('view queue') || l.contains('queue detail') ||
        l.contains('monitor')) {
      appState.addBotText("Taking you to your queue status now. 👁");
      setState(() => _sending = false);
      _scrollToBottom();
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) widget.onViewQueue();
      return true;
    }

    // 8. Select / change clinic — lets the patient pick explicitly instead
    // of only relying on an active queue or appointment.
    if (l.contains('select clinic') || l.contains('choose clinic') ||
        l.contains('pick clinic') || l.contains('change clinic')) {
      await _pickClinic();
      if (_selectedClinicId != null) {
        appState.addBotText(
          "Got it — I'll route any staff requests to $_selectedClinicName.",
          quickReplies: ['Talk to staff'],
        );
      }
      return true;
    }

    // 9. Talk to staff / escalate
    if (l.contains('talk to staff') || l.contains('staff') ||
        l.contains('human') || l.contains('real person') ||
        l.contains('escalate') || l.contains('complaint')) {
      await _escalateToStaff(appState, note: msg);
      return true;
    }

    // 10. Greetings — handle locally, no server round-trip needed
    if (l == 'hi' || l == 'hello' || l == 'hey' || l == 'hi po' ||
        l == 'hello po' || l.startsWith('good morning') ||
        l.startsWith('good afternoon') || l.startsWith('good evening') ||
        l == 'musta' || l == 'kumusta') {
      appState.addBotText(
        "Hi there! 👋 I'm HQ Assistant. I can help you with:\n"
        "• Queue status & joining a queue\n"
        "• Booking appointments\n"
        "• Finding nearby clinics\n"
        "• Wait times & clinic info\n\n"
        "What can I help you with today?",
        quickReplies: ['Join the queue', 'Book an appointment', 'Find clinic near me'],
      );
      return true;
    }

    // 11. Thanks / done
    if (l == 'thanks' || l == 'thank you' || l == 'salamat' ||
        l == 'ok thanks' || l == 'thank you po' || l == 'salamat po') {
      appState.addBotText(
        "You're welcome! 😊 Is there anything else I can help you with?",
        quickReplies: ['Check my queue status', 'Find clinic near me'],
      );
      return true;
    }

    return false; // not handled locally → go to server
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _sending) return;
    _inputCtrl.clear();
    setState(() => _sending = true);

    final appState = context.read<AppState>();
    appState.addUserText(msg);
    _scrollToBottom();

    // Always try the server first so the configured Rasa chatbot is actually
    // used. Local handling remains the offline fallback below.
    // ── Send to server (Rasa → OpenAI → FAQ chain) ────────────────────────
    try {
      final res = await ApiService.sendChatMessage(msg);

      // Server returns { response, reply, source, isEscalated, logId } —
      // or, once a conversation has been escalated and staff have taken
      // over, { response: null, awaitingStaff: true } instead of a bot
      // reply (see chatbotController.handleMessage's staff-handoff check).
      final reply = (res['response'] ?? res['reply'] ?? res['answer'] ?? '')
          .toString().trim();
      _lastLogId = res['logId']?.toString();

      if (res['awaitingStaff'] == true) {
        appState.setAwaitingStaff(true);
        // No canned bot text here — the message was relayed to staff, not
        // answered. A separate "Staff notified" / typing-style indicator
        // in the UI communicates this; showing a bot reply would look
        // like the assistant is still driving the conversation.
      } else if (reply.isEmpty) {
        // Server returned empty — shouldn't happen with the new controller
        appState.addBotText(
          "I'm not sure about that. Try asking about wait times, appointments, or finding a clinic.",
          quickReplies: ['Estimated wait time', 'Book an appointment', 'Find clinic near me'],
        );
      } else {
        appState.addBotText(reply);
      }

      // If server flagged this for escalation, update UI AND leave a clear
      // confirmation in the chat feed — the header badge alone is easy to
      // miss, which was leaving patients unsure whether anything actually
      // happened.
      if (res['isEscalated'] == true) {
        setState(() => _escalated = true);
        final clinicName = _effectiveClinicName(appState);
        appState.addBotText(
          "✅ I've flagged this to staff${clinicName != null ? ' at $clinicName' : ''}. "
          "They'll follow up shortly. You'll see a \"Staff notified\" badge above while it's pending.",
        );
      }
    } catch (e) {
      // If Rasa/API is unavailable, keep the old local shortcuts as fallback.
      final handledLocally = await _handleLocally(msg, appState);
      if (!handledLocally) {
        appState.addBotText(
          "I couldn't reach the AI assistant right now. You can still check your queue, book an appointment, or find a clinic.",
          quickReplies: ['Check my queue status', 'Book an appointment', 'Find clinic near me'],
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

@override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final messages = appState.messages;
    final clinicChipLabel = _effectiveClinicName(appState) ?? 'Select clinic';

    return SafeArea(
      bottom: false, // Prevents interfering with the keyboard and bottom input bar
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                      color: Colors.white24, shape: BoxShape.circle),
                  child: const Icon(Icons.smart_toy_outlined,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HQ Assistant',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                      Text('Ask me anything about your clinic visit',
                          style: TextStyle(color: Colors.white60, fontSize: 10)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _pickClinic,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    margin: const EdgeInsets.only(right: 6),
                    constraints: const BoxConstraints(maxWidth: 110),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(99)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_hospital_outlined,
                            size: 11, color: Colors.white),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(clinicChipLabel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_escalated)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(99)),
                    child: const Text('Staff notified',
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),

          // ── Messages ───────────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              itemCount: messages.length + (_sending ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (_sending && i == messages.length) return _typingBubble();
                final m = messages[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MessageBubble(msg: m),
                    if (!m.isUser && m.quickReplies.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 36, bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: m.quickReplies
                              .map((q) => GestureDetector(
                                    onTap: () => _send(q),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(99),
                                        border: Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: .4)),
                                      ),
                                      child: Text(q,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary)),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // ── Persistent quick reply chips ───────────────────────────────────
          Container(
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                  children: _quickReplies
                      .map((q) => GestureDetector(
                            onTap: () => _send(q),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                    color: AppColors.primary.withValues(alpha: .3)),
                              ),
                              child: Text(q,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary)),
                            ),
                          ))
                      .toList()),
            ),
          ),

          // ── Input bar ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    blurRadius: 10,
                    color: Colors.black.withValues(alpha: .06),
                    offset: const Offset(0, -2))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    onSubmitted: _send,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Ask HQ Assistant…',
                      hintStyle:
                          const TextStyle(fontSize: 13, color: Colors.black38),
                      filled: true,
                      fillColor: const Color(0xFFF6F7FB),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _send(_inputCtrl.text),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: _sending ? Colors.grey.shade300 : AppColors.primary,
                        shape: BoxShape.circle),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingBubble() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      _avatar(),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          _Dot(delay: Duration.zero),
          SizedBox(width: 4),
          _Dot(delay: Duration(milliseconds: 180)),
          SizedBox(width: 4),
          _Dot(delay: Duration(milliseconds: 360)),
        ]),
      ),
    ]),
  );

  Widget _avatar() => Container(
    width: 28, height: 28,
    decoration: const BoxDecoration(
        color: Color(0xFF2563EB), shape: BoxShape.circle),
    child: const Icon(Icons.smart_toy_outlined,
        size: 16, color: Colors.white),
  );
}

// ── Message bubble ─────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                  color: msg.isStaff
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF2563EB),
                  shape: BoxShape.circle),
              child: Icon(
                  msg.isStaff ? Icons.support_agent : Icons.smart_toy_outlined,
                  size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? AppColors.primary
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4  : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(color: Colors.grey.shade100),
                boxShadow: [BoxShadow(
                    blurRadius: 4,
                    color: Colors.black.withValues(alpha: .05),
                    offset: const Offset(0, 1))],
              ),
              child: Text(msg.text,
                  style: TextStyle(
                      fontSize: 13,
                      color: isUser ? Colors.white : const Color(0xFF1F2937),
                      height: 1.5)),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ── Clinic picker sheet ─────────────────────────────────────────────────────────
// Lets the patient explicitly choose which clinic a staff escalation (or the
// conversation in general) should be routed to. Pops {'id', 'name'} for the
// tapped clinic, or null if dismissed.
class _ClinicPickerSheet extends StatelessWidget {
  final List<dynamic> clinics;
  const _ClinicPickerSheet({required this.clinics});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99))),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Select a Clinic',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: AppColors.textDark)),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: clinics.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (ctx, i) {
                  final raw = clinics[i];
                  final m = raw is Map
                      ? Map<String, dynamic>.from(raw)
                      : <String, dynamic>{};
                  final id = m['_id']?.toString() ?? m['id']?.toString() ?? '';
                  final name = m['name']?.toString() ?? 'Clinic';
                  final address = m['address']?.toString() ??
                      m['city']?.toString() ??
                      '';
                  return ListTile(
                    leading: const Icon(Icons.local_hospital_outlined,
                        color: AppColors.primary),
                    title: Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: address.isNotEmpty
                        ? Text(address, style: const TextStyle(fontSize: 11))
                        : null,
                    onTap: id.isEmpty
                        ? null
                        : () => Navigator.pop(context, {'id': id, 'name': name}),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Animated typing dot ────────────────────────────────────────────────────────
class _Dot extends StatefulWidget {
  final Duration delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500));
    Future.delayed(widget.delay, () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Container(
      width: 7, height: 7,
      decoration: BoxDecoration(
        color: Color.lerp(Colors.grey.shade300,
            AppColors.primary, _c.value),
        shape: BoxShape.circle,
      ),
    ),
  );
}
