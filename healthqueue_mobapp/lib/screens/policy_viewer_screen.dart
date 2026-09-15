import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// Full Terms & Agreements + Privacy Policy viewer, shown before a patient
/// can register (Capstone requirement #2/#3). Pushed from register_screen's
/// agreement row instead of that row just being static text — the
/// checkbox there stays disabled until this screen reports back that the
/// user actually reached the bottom of BOTH documents, not just tapped a
/// link that happened to exist.
///
/// Content below is transcribed directly from the project's own
/// privacy_policy.txt / terms_and_agreements.txt (the React source used on
/// the web client) so the two surfaces stay in agreement — this is not
/// placeholder text.
class PolicyViewerScreen extends StatefulWidget {
  const PolicyViewerScreen({super.key});

  @override
  State<PolicyViewerScreen> createState() => _PolicyViewerScreenState();
}

class _PolicyViewerScreenState extends State<PolicyViewerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _termsScrollCtrl = ScrollController();
  final _privacyScrollCtrl = ScrollController();

  bool _termsReachedBottom = false;
  bool _privacyReachedBottom = false;

  bool get _bothReached => _termsReachedBottom && _privacyReachedBottom;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _termsScrollCtrl.addListener(() => _checkBottom(_termsScrollCtrl, isTerms: true));
    _privacyScrollCtrl.addListener(() => _checkBottom(_privacyScrollCtrl, isTerms: false));
    // Handles the case where the content is already short enough to fit
    // without scrolling at all (item 3's explicit edge case) — if there's
    // nothing to scroll, maxScrollExtent is 0/near-0 on the very first
    // frame, so treat that as "reached the end" rather than leaving the
    // user stuck with a Continue button that can never unlock because a
    // scroll event that would trigger _checkBottom simply never fires.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBottom(_termsScrollCtrl, isTerms: true);
      _checkBottom(_privacyScrollCtrl, isTerms: false);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _termsScrollCtrl.dispose();
    _privacyScrollCtrl.dispose();
    super.dispose();
  }

  void _checkBottom(ScrollController ctrl, {required bool isTerms}) {
    if (!ctrl.hasClients) return;
    // 24px tolerance — physical scroll positions rarely land on an exact
    // pixel, and requiring literally 0px left would make "did they reach
    // the bottom" flaky on some devices.
    final atBottom = ctrl.position.maxScrollExtent <= 0 ||
        ctrl.position.pixels >= ctrl.position.maxScrollExtent - 24;
    if (!atBottom) return;
    setState(() {
      if (isTerms) {
        _termsReachedBottom = true;
      } else {
        _privacyReachedBottom = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text('Terms & Privacy Policy',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_termsReachedBottom)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_circle, size: 13, color: Color(0xFF16A34A)),
                ),
              const Text('Terms & Agreements'),
            ])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_privacyReachedBottom)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_circle, size: 13, color: Color(0xFF16A34A)),
                ),
              const Text('Privacy Policy'),
            ])),
          ],
        ),
      ),
      body: Column(children: [
        if (!_bothReached)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFFBEB),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 15, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tabCtrl.index == 0 && !_termsReachedBottom
                      ? 'Please scroll to the bottom of the Terms & Agreements.'
                      : _tabCtrl.index == 1 && !_privacyReachedBottom
                          ? 'Please scroll to the bottom of the Privacy Policy.'
                          : 'Please read both documents in full to continue.',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                ),
              ),
            ]),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _scrollableDoc(_termsScrollCtrl, _termsContent()),
              _scrollableDoc(_privacyScrollCtrl, _privacyContent()),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: .06),
                blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _bothReached
                  ? () => Navigator.pop(context, true)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _bothReached ? "I've Read This — Continue" : 'Keep scrolling to continue',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _scrollableDoc(ScrollController ctrl, List<Widget> children) {
    return Scrollbar(
      controller: ctrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }

  Widget _h1(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark)),
      );
  Widget _h2(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t, style: const TextStyle(
            fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textDark)),
      );
  Widget _p(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 13, height: 1.55, color: Color(0xFF374151))),
      );
  Widget _li(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: CircleAvatar(radius: 2.5, backgroundColor: AppColors.textMuted),
          ),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 13, height: 1.55, color: Color(0xFF374151)))),
        ]),
      );
  Widget _effectiveDate() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text.rich(TextSpan(children: [
          const TextSpan(text: 'Effective Date: ',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.textMuted)),
          const TextSpan(text: 'June 03, 2026',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        ])),
      );

  List<Widget> _termsContent() => [
        _h1('HealthQueue+ Terms and Agreements'),
        _effectiveDate(),
        _p('By creating and using a HealthQueue+ account, you agree to these Terms and Agreements.'),

        _h2('1. Use of HealthQueue+'),
        _p('HealthQueue+ provides appointment scheduling, queue enrollment and monitoring, waiting-time forecasts, clinic recommendations, chatbot assistance, and related services.'),
        _p('You agree to provide accurate information and use the system only for its intended and lawful purposes.'),

        _h2('2. Appointments and Queues'),
        _p('Users are responsible for selecting the correct clinic and appointment schedule and for monitoring their queue status.'),
        _p("Where applicable, patients may join a queue while on the way to the clinic. A five-minute grace period may apply once it is the patient's turn. Missed turns may be skipped or removed according to the clinic's queue policy."),

        _h2('3. Waiting-Time Forecasts'),
        _p('HealthQueue+ provides estimated waiting times based on available queue information.'),
        _p('These forecasts are estimates only and may change due to patient volume, clinic operations, staff availability, or other circumstances.'),

        _h2('4. Clinic Recommendations'),
        _p('HealthQueue+ may recommend clinics based on factors such as location, distance, queue conditions, or estimated waiting time.'),
        _p("Recommendations are provided for convenience and do not guarantee clinic availability, service, or suitability for a user's medical needs."),

        _h2('5. AI and Chatbot'),
        _p('AI-assisted features and the chatbot are provided for general system assistance.'),
        _p('AI-generated information may not always be accurate and must not be treated as medical advice, diagnosis, or treatment.'),

        _h2('6. User Responsibilities'),
        _p('Users must not:'),
        _li('Provide false or misleading information;'),
        _li("Access another person's account;"),
        _li('Attempt to bypass system security;'),
        _li('Manipulate queue or appointment information;'),
        _li('Interfere with system operations; or'),
        _li('Use the system for unlawful purposes.'),

        _h2('7. System Availability'),
        _p('HealthQueue+ may occasionally be unavailable due to maintenance, technical problems, internet issues, or third-party service interruptions.'),

        _h2('8. Privacy'),
        _p('Your use of HealthQueue+ is also subject to the HealthQueue+ Privacy Policy, which explains how your personal information is collected and processed.'),

        _h2('9. Contact Us'),
        _p('For questions or concerns, you may contact us at:'),
        _p('Email: healthqueueorg@gmail.com'),

        const SizedBox(height: 8),
        _p('By checking the agreement box, you confirm that you have read, understood, and agree to these Terms and Agreements.'),
      ];

  List<Widget> _privacyContent() => [
        _h1('HealthQueue+ Privacy Policy'),
        _effectiveDate(),
        _p('HealthQueue+ respects your privacy and is committed to protecting your personal information in accordance with the Data Privacy Act of 2012 (RA 10173).'),

        _h2('Information We Collect'),
        _p('HealthQueue+ may collect information needed to provide its services, including your:'),
        _li('Name'),
        _li('Email address'),
        _li('Mobile number'),
        _li('Appointment and queue information'),
        _li('Location, when you allow location access'),
        _li('Feedback and system activity'),

        _h2('How We Use Your Information'),
        _p('Your information may be used to:'),
        _li('Create and manage your account;'),
        _li('Verify your account through OTP;'),
        _li('Process appointments and queue enrollment;'),
        _li('Monitor your queue and provide estimated waiting times;'),
        _li('Recommend nearby clinics;'),
        _li('Provide chatbot and AI-assisted features;'),
        _li('Improve the system; and'),
        _li('Maintain system security.'),
        _p('HealthQueue+ is primarily a queue and appointment management system and is not intended to collect or store medical records.'),

        _h2('AI and Location'),
        _p('HealthQueue+ may use queue information such as waiting time, turnaround time, queue count, and peak periods to provide estimated waiting times and queue-related recommendations.'),
        _p('These are estimates only and are not medical advice or diagnosis.'),
        _p('Location information is used for location-based features, such as recommending nearby clinics. You may deny location access, but location-based features may not be available.'),

        _h2('Data Sharing and Security'),
        _p('HealthQueue+ does not sell your personal information. Information may be shared with authorized clinic personnel and trusted service providers when necessary to operate system features such as OTP, maps, AI, chatbot, and hosting services.'),
        _p('Reasonable security measures are implemented to protect your information from unauthorized access or misuse.'),

        _h2('Your Rights'),
        _p('Under the Data Privacy Act, you may have the right to access, correct, object to the processing of, or request the deletion or blocking of your personal information where applicable.'),

        _h2('Contact Us'),
        _p('For privacy concerns, you may contact us at:'),
        _p('Email: healthqueueorg@gmail.com'),

        const SizedBox(height: 8),
        _p('By using HealthQueue+, you acknowledge that you have read and understood this Privacy Policy.'),
      ];
}
