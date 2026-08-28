import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';
import '../../models/call_log_model.dart';
import '../login_screen.dart';

class CallyzerSetupFlow extends StatefulWidget {
  const CallyzerSetupFlow({super.key});

  @override
  State<CallyzerSetupFlow> createState() => _CallyzerSetupFlowState();
}

class _CallyzerSetupFlowState extends State<CallyzerSetupFlow> {
  int _currentStep = 0;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  int _selectedSimSlot = 0;

  // Accordion open states for Privacy screen
  bool _dataProcessOpen = false;
  bool _useDataOpen = false;
  bool _unnecessaryPermsOpen = false;
  bool _termsAccepted = false;

  String _clean10DigitPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tele = Provider.of<TeleProvider>(context, listen: false);
      if (tele.callerName.isNotEmpty) {
        _nameController.text = tele.callerName;
      }
      tele.fetchDeviceSims().then((_) {
        if (mounted && tele.detectedSims.isNotEmpty) {
          setState(() {
            _selectedSimSlot = tele.detectedSims[0].slotIndex;
            if (tele.detectedSims[0].phoneNumber.isNotEmpty) {
              _phoneController.text = _clean10DigitPhone(tele.detectedSims[0].phoneNumber);
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _nextStep() {
    setState(() {
      _currentStep++;
    });
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  void _finishSetup(TeleProvider tele) {
    tele.completeSetup(
      mode: _selectedSimSlot == 0 ? SimTrackingMode.sim1Only : SimTrackingMode.sim2Only,
      callerName: _nameController.text.trim(),
    );

    // Show Success Toast
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.ink900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.greenNeon, width: 1),
        ),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppTheme.greenNeon, size: 20),
            const SizedBox(width: 10),
            Text(
              'SIM ${_selectedSimSlot + 1} is verified successfully !',
              style: AppTheme.bodyBold(size: 13, color: AppTheme.white),
            ),
          ],
        ),
      ),
    );

    _showWhatsNewDialog(context);
  }

  void _showWhatsNewDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: NeoCard(
            backgroundColor: AppTheme.white,
            shadowColor: AppTheme.ink900,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.campaign, size: 54, color: AppTheme.greenDark),
                const SizedBox(height: 10),
                Text('What\'s New', style: AppTheme.headline(size: 26)),
                Text('1.1.2', style: AppTheme.label(size: 10, color: AppTheme.muted)),
                const SizedBox(height: 16),
                _whatsNewItem('Added new troubleshooting options to help users easily manage and resolve permission-related issues.'),
                _whatsNewItem('Improved performance for a smoother and faster telesales experience.'),
                _whatsNewItem('Bug fixes and stability improvements for better call reliability.'),
                _whatsNewItem('Overall enhancements to make your daily telesales usage simple and efficient.'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: NeoButton.pill(
                    backgroundColor: AppTheme.greenNeon,
                    shadowColor: AppTheme.ink900,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: () => Navigator.pop(ctx),
                    child: Center(
                      child: Text(
                        'Got it !',
                        style: AppTheme.headline(size: 16, color: AppTheme.ink900),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _whatsNewItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, size: 16, color: AppTheme.greenDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppTheme.body(size: 12, color: AppTheme.ink700)),
          ),
        ],
      ),
    );
  }

  void _showVerifyViaCallLogModal(BuildContext context, TeleProvider tele) {
    final phone = _phoneController.text.isNotEmpty ? '+91${_phoneController.text}' : '+91 98250 12340';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
              ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 24),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.ink900.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.ink900),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Select a Call Log which has been dialed with this SIM number $phone.',
                style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
              ),
              const SizedBox(height: 16),
              if (tele.allCallLogs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No device call logs found yet.\nTap Skip Verification or make a test call.',
                      textAlign: TextAlign.center,
                      style: AppTheme.body(size: 12, color: AppTheme.muted),
                    ),
                  ),
                )
              else
                ...tele.allCallLogs.take(4).map((c) {
                  final timeStr = DateFormat('yyyy-MM-dd hh:mm a').format(c.timestamp);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CallLogSelectCard(
                      name: c.contactName,
                      phone: c.phoneNumber,
                      time: timeStr,
                      duration: c.durationFormatted,
                      isOutgoing: c.type == CallType.outgoing,
                      onSelect: () {
                        Navigator.pop(ctx);
                        _finishSetup(tele);
                      },
                    ),
                  );
                }),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildCurrentStep(context, tele),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep(BuildContext context, TeleProvider tele) {
    switch (_currentStep) {
      case 0:
        return _buildPrivacyStep();
      case 1:
        return _buildCallLogStep(tele);
      case 2:
        return _buildDefaultDialerStep();
      case 3:
        return _buildContactsStep(tele);
      case 4:
        return _buildConnectSimStep(tele);
      case 5:
        return _buildSimVerificationStep(tele);
      default:
        return _buildPrivacyStep();
    }
  }

  // ================= STEP 0: PRIVACY POLICY =================
  Widget _buildPrivacyStep() {
    return SingleChildScrollView(
      key: const ValueKey('step_0_privacy'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            'Your privacy is important to us',
            style: AppTheme.headline(size: 26, color: AppTheme.ink900),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Please take time to review the key points of our ',
                  style: AppTheme.body(size: 13, color: AppTheme.ink700),
                ),
                TextSpan(
                  text: 'Privacy Policy',
                  style: AppTheme.bodyBold(size: 13, color: AppTheme.greenDark),
                ),
                TextSpan(
                  text: ' below.',
                  style: AppTheme.body(size: 13, color: AppTheme.ink700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Accordion 1: Data we process
          _AccordionCard(
            title: 'Data we process',
            isOpen: _dataProcessOpen,
            onToggle: () => setState(() => _dataProcessOpen = !_dataProcessOpen),
            content: 'We process call log timestamps, call durations, phone numbers, and call state events (incoming, outgoing, missed) exclusively to compute telesales performance analytics.',
          ),
          const SizedBox(height: 12),

          // Accordion 2: How we use your data
          _AccordionCard(
            title: 'How we use your data',
            isOpen: _useDataOpen,
            onToggle: () => setState(() => _useDataOpen = !_useDataOpen),
            content: 'Your call data is stored securely on your local device and synced with your team manager dashboard. We never sell your personal contact or call data to third parties.',
          ),
          const SizedBox(height: 12),

          // Accordion 3: Unnecessary permissions? We never ask for it
          _AccordionCard(
            title: 'Unnecessary permissions? We never ask for it',
            isOpen: _unnecessaryPermsOpen,
            onToggle: () => setState(() => _unnecessaryPermsOpen = !_unnecessaryPermsOpen),
            content: 'We only request permissions strictly needed for telesales monitoring: Call Log access, Phone State for SIM slot detection, and Contacts access for customer mapping.',
          ),
          const SizedBox(height: 36),

          // Consent Box with Mandatory Terms & Conditions Checkbox
          GestureDetector(
            onTap: () => setState(() => _termsAccepted = !_termsAccepted),
            child: NeoCard(
              backgroundColor: _termsAccepted ? const Color(0xFFF0FDF4) : AppTheme.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: _termsAccepted,
                    activeColor: AppTheme.ink900,
                    checkColor: AppTheme.limeYellow,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (val) => setState(() => _termsAccepted = val ?? false),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'I agree to the ',
                            style: AppTheme.body(size: 12, color: AppTheme.ink900),
                          ),
                          TextSpan(
                            text: 'Terms & Conditions',
                            style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900),
                          ),
                          TextSpan(
                            text: ' and ',
                            style: AppTheme.body(size: 12, color: AppTheme.ink900),
                          ),
                          TextSpan(
                            text: 'Privacy Policy.',
                            style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Agree & Continue Button (Requires Checkbox)
          Opacity(
            opacity: _termsAccepted ? 1.0 : 0.5,
            child: NeoButton.accent(
              gradient: null,
              backgroundColor: AppTheme.greenNeon,
              padding: const EdgeInsets.symmetric(vertical: 16),
              onTap: _termsAccepted ? _nextStep : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.ink900,
                    content: Text(
                      'Please check the Terms & Conditions box to continue.',
                      style: AppTheme.body(size: 12, color: AppTheme.limeYellow),
                    ),
                  ),
                );
              },
              child: Center(
                child: Text(
                  'AGREE & CONTINUE',
                  style: AppTheme.headline(size: 16, color: AppTheme.ink900),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= STEP 1: ACCESS TO CALL LOG =================
  Widget _buildCallLogStep(TeleProvider tele) {
    return SingleChildScrollView(
      key: const ValueKey('step_1_call_log'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 180,
              height: 150,
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(),
              ),
              child: const Icon(Icons.phone_in_talk, size: 64, color: AppTheme.greenDark),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'ACCESS TO YOUR DEVICE\'S CALL LOG',
            textAlign: TextAlign.center,
            style: AppTheme.headline(size: 22, color: AppTheme.ink900),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Why we need this permission:', style: AppTheme.bodyBold(size: 13)),
          ),
          const SizedBox(height: 6),
          Text(
            'Your default dialer only shows your call history. Telesales Monitor helps you understand it.\n\n'
            'We require access to your call history to provide core features: generating insights, talk time summaries, and detailed reports about caller activity.',
            style: AppTheme.body(size: 12.5, color: AppTheme.ink700),
          ),
          const SizedBox(height: 12),
          Text(
            'All data is processed locally and remains securely stored on your device.',
            style: AppTheme.body(size: 12, color: AppTheme.muted),
          ),
          const SizedBox(height: 28),
          NeoButton.accent(
            gradient: null,
            backgroundColor: AppTheme.greenNeon,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: () async {
              await tele.requestNativePermissions();
              _nextStep();
            },
            child: Center(
              child: Text(
                'Allow Access',
                style: AppTheme.headline(size: 16, color: AppTheme.ink900),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 14, color: AppTheme.ink900),
              const SizedBox(width: 6),
              Text('It is Secure!', style: AppTheme.bodyBold(size: 12)),
              const Text(' · '),
              Text('Privacy Policy', style: AppTheme.body(size: 12, color: AppTheme.greenDark)),
            ],
          ),
        ],
      ),
    );
  }

  // ================= STEP 2: SET DEFAULT PHONE APP =================
  Widget _buildDefaultDialerStep() {
    return SingleChildScrollView(
      key: const ValueKey('step_2_default_app'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 180,
              height: 150,
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(),
              ),
              child: const Icon(Icons.support_agent, size: 64, color: AppTheme.greenNeon),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Set Default Phone App',
            style: AppTheme.headline(size: 24, color: AppTheme.ink900),
          ),
          const SizedBox(height: 12),
          Text(
            'To seamlessly capture call states and automatically track live telesales leads without manual logging, set Telesales Monitor as your default phone companion.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13, color: AppTheme.ink700),
          ),
          const SizedBox(height: 24),

          // Mock System Prompt Box
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone_android, size: 24, color: AppTheme.greenDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Set Telesales Monitor as your default phone app?',
                        style: AppTheme.bodyBold(size: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _RadioItem(title: 'Telesales Monitor', isSelected: true),
                const SizedBox(height: 8),
                _RadioItem(title: 'System Phone (Current default)', isSelected: false),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _nextStep,
                      child: Text('Cancel', style: AppTheme.bodyBold(size: 12, color: AppTheme.muted)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.ink900,
                        foregroundColor: AppTheme.white,
                      ),
                      onPressed: _nextStep,
                      child: const Text('Set as default'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= STEP 3: CONTACTS ACCESS =================
  Widget _buildContactsStep(TeleProvider tele) {
    return SingleChildScrollView(
      key: const ValueKey('step_3_contacts'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 180,
              height: 150,
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(),
              ),
              child: const Icon(Icons.contacts, size: 64, color: AppTheme.greenDark),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Contacts Access',
              style: AppTheme.headline(size: 26, color: AppTheme.ink900),
            ),
          ),
          const SizedBox(height: 14),
          Text('Why we need this permission:', style: AppTheme.bodyBold(size: 13)),
          const SizedBox(height: 6),
          Text(
            'Access to contacts allows Telesales Monitor to map phone numbers to saved client names and details. This improves the accuracy and readability of your lead pipeline and reports.',
            style: AppTheme.body(size: 12.5, color: AppTheme.ink700),
          ),
          const SizedBox(height: 14),
          Text('What we use it for:', style: AppTheme.bodyBold(size: 13)),
          const SizedBox(height: 8),
          _BulletPoint('Display customer names instead of raw phone numbers'),
          _BulletPoint('Show profile avatars in your caller listing'),
          _BulletPoint('Match call log entries with the right CRM lead'),
          const SizedBox(height: 28),
          NeoButton.accent(
            gradient: null,
            backgroundColor: AppTheme.greenNeon,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: () async {
              await tele.requestNativePermissions();
              _nextStep();
            },
            child: Center(
              child: Text(
                'Let\'s do it',
                style: AppTheme.headline(size: 16, color: AppTheme.ink900),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 14, color: AppTheme.ink900),
              const SizedBox(width: 6),
              Text('It is Secure!', style: AppTheme.bodyBold(size: 12)),
              const Text(' · '),
              Text('Privacy Policy', style: AppTheme.body(size: 12, color: AppTheme.greenDark)),
            ],
          ),
        ],
      ),
    );
  }

  // ================= STEP 4: CONNECT SIM =================
  Widget _buildConnectSimStep(TeleProvider tele) {
    final sims = tele.detectedSims;

    return SingleChildScrollView(
      key: const ValueKey('step_4_connect_sim'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppTheme.ink900),
                    onPressed: _prevStep,
                  ),
                  const SizedBox(width: 4),
                  Text('Connect Sim', style: AppTheme.headline(size: 22)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppTheme.greenDark, size: 20),
                tooltip: 'Refresh SIMs',
                onPressed: () => tele.fetchDeviceSims(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppTheme.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Due to Latest Android Policy we verify your phone number to attach call telemetry to your SIM slot.',
                    style: AppTheme.body(size: 11, color: AppTheme.ink700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Auto-Detected SIM Cards from Android Hardware
          Text('AUTO-DETECTED SIM CARDS', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
          const SizedBox(height: 8),

          if (sims.isEmpty) ...[
            Text('Scanning device SIM slots...', style: AppTheme.body(size: 12, color: AppTheme.muted)),
          ] else ...[
            for (var sim in sims) ...[
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedSimSlot = sim.slotIndex;
                    if (sim.phoneNumber.isNotEmpty) {
                      _phoneController.text = _clean10DigitPhone(sim.phoneNumber);
                    }
                  });
                },
                child: NeoCard(
                  backgroundColor: _selectedSimSlot == sim.slotIndex ? AppTheme.ink900 : AppTheme.white,
                  shadowColor: _selectedSimSlot == sim.slotIndex ? AppTheme.greenNeon : AppTheme.ink900,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _selectedSimSlot == sim.slotIndex ? AppTheme.greenNeon : AppTheme.ink900,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${sim.slotIndex + 1}',
                              style: AppTheme.mono(
                                size: 12,
                                color: _selectedSimSlot == sim.slotIndex ? AppTheme.ink900 : AppTheme.limeYellow,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${sim.displayName} | ${sim.carrierName}',
                                style: AppTheme.bodyBold(
                                  size: 13,
                                  color: _selectedSimSlot == sim.slotIndex ? AppTheme.white : AppTheme.ink900,
                                ),
                              ),
                              if (sim.phoneNumber.isNotEmpty)
                                Text(
                                  sim.phoneNumber,
                                  style: AppTheme.mono(
                                    size: 10,
                                    color: _selectedSimSlot == sim.slotIndex ? AppTheme.lightMuted : AppTheme.muted,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (_selectedSimSlot == sim.slotIndex)
                        const Icon(Icons.check_circle, color: AppTheme.greenNeon, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],

          const SizedBox(height: 16),

          Text('MOBILE NUMBER', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
          const SizedBox(height: 6),

          // Clean single phone input box (No +91 country box)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.ink900, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_android_rounded, size: 20, color: AppTheme.ink900),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: AppTheme.mono(size: 16, color: AppTheme.ink900),
                    decoration: const InputDecoration(
                      hintText: 'Enter 10-digit mobile number...',
                      hintStyle: TextStyle(fontSize: 13, color: AppTheme.muted),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Submit Button
          NeoButton.accent(
            gradient: null,
            backgroundColor: AppTheme.greenNeon,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: () async {
              final raw = _clean10DigitPhone(_phoneController.text);
              if (raw.isEmpty || raw.length != 10) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.ink900,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.greenNeon, width: 1.5),
                    ),
                    content: Text(
                      'Please enter a valid 10-digit mobile number.',
                      style: AppTheme.bodyBold(size: 12, color: AppTheme.white),
                    ),
                  ),
                );
                return;
              }

              // Show loading overlay / feedback
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.ink900,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  content: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.limeYellow),
                      ),
                      const SizedBox(width: 12),
                      Text('Verifying mobile number with team records...', style: AppTheme.body(size: 12, color: AppTheme.white)),
                    ],
                  ),
                ),
              );

              final res = await tele.validateAndSetTrackingNumber(raw, _selectedSimSlot);
              if (!mounted) return;

              if (res['isValid'] == true) {
                // Show Success Toast
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.ink900,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.greenNeon, width: 1.5),
                    ),
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: AppTheme.greenNeon, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            res['message'] as String? ?? 'SIM connected & mobile number verified successfully!',
                            style: AppTheme.bodyBold(size: 12, color: AppTheme.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                // Navigate directly to LoginScreen
                await Future.delayed(const Duration(milliseconds: 600));
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              } else {
                // Show Failure Dialog
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppTheme.paper,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: AppTheme.ink900, width: 2),
                    ),
                    title: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 24),
                        const SizedBox(width: 8),
                        Text('Verification Failed', style: AppTheme.headline(size: 18)),
                      ],
                    ),
                    content: Text(
                      res['message'] as String? ?? 'Mobile number not found in database. Please contact your manager or admin.',
                      style: AppTheme.body(size: 13, color: AppTheme.ink900),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('OK', style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900)),
                      ),
                    ],
                  ),
                );
              }
            },
            child: Center(
              child: Text(
                'SUBMIT',
                style: AppTheme.headline(size: 16, color: AppTheme.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= STEP 5: SIM NUMBER VERIFICATION =================
  Widget _buildSimVerificationStep(TeleProvider tele) {
    final phone = _phoneController.text.isNotEmpty ? '+91 ${_phoneController.text}' : '+91 98250 12340';

    return SingleChildScrollView(
      key: const ValueKey('step_5_verify_sim'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.ink900),
                onPressed: _prevStep,
              ),
              const SizedBox(width: 4),
              Text('SIM Number', style: AppTheme.headline(size: 22)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Choose one of the option to verify your number',
            style: AppTheme.headline(size: 20, color: AppTheme.ink900),
          ),
          const SizedBox(height: 20),

          // Option 1: Verify via Call Log
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            onTap: () => _showVerifyViaCallLogModal(context, tele),
            child: Row(
              children: [
                const Icon(Icons.history_toggle_off, size: 24, color: AppTheme.ink900),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verify via Call Log', style: AppTheme.bodyBold(size: 14)),
                      const SizedBox(height: 3),
                      Text(
                        'App will show few call logs and you need to simply select which call you have dialed using $phone.',
                        style: AppTheme.body(size: 11, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.ink900),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Option 2: Verify via Call
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            onTap: () => _finishSetup(tele),
            child: Row(
              children: [
                const Icon(Icons.call, size: 24, color: AppTheme.ink900),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verify via Call', style: AppTheme.bodyBold(size: 14)),
                      const SizedBox(height: 3),
                      Text(
                        'App will make a test verification call to your number itself.',
                        style: AppTheme.body(size: 11, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.ink900),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Option 3: Skip Verification
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            onTap: () => _finishSetup(tele),
            child: Row(
              children: [
                const Icon(Icons.block, size: 24, color: AppTheme.muted),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Skip Verification', style: AppTheme.bodyBold(size: 14)),
                      const SizedBox(height: 3),
                      Text(
                        '(Not Recommended)\nVerification process will be skipped and you can start tracking immediately.',
                        style: AppTheme.body(size: 11, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccordionCard extends StatelessWidget {
  final String title;
  final String content;
  final bool isOpen;
  final VoidCallback onToggle;

  const _AccordionCard({
    required this.title,
    required this.content,
    required this.isOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return NeoCard(
      padding: const EdgeInsets.all(14),
      onTap: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(title, style: AppTheme.bodyBold(size: 13)),
              ),
              const SizedBox(width: 8),
              Icon(isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 10),
            Text(content, style: AppTheme.body(size: 12, color: AppTheme.ink700)),
          ],
        ],
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          Expanded(child: Text(text, style: AppTheme.body(size: 12, color: AppTheme.ink700))),
        ],
      ),
    );
  }
}

class _RadioItem extends StatelessWidget {
  final String title;
  final bool isSelected;
  const _RadioItem({required this.title, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 18,
          color: isSelected ? AppTheme.greenDark : AppTheme.muted,
        ),
        const SizedBox(width: 8),
        Text(title, style: AppTheme.body(size: 12, color: AppTheme.ink900)),
      ],
    );
  }
}

class _CallLogSelectCard extends StatelessWidget {
  final String name;
  final String phone;
  final String time;
  final String duration;
  final bool isOutgoing;
  final VoidCallback onSelect;

  const _CallLogSelectCard({
    required this.name,
    required this.phone,
    required this.time,
    required this.duration,
    required this.isOutgoing,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return NeoCard(
      padding: const EdgeInsets.all(14),
      onTap: onSelect,
      child: Row(
        children: [
          const Icon(Icons.radio_button_unchecked, color: AppTheme.muted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTheme.bodyBold(size: 13)),
                Text(phone, style: AppTheme.mono(size: 11, color: AppTheme.muted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(time, style: AppTheme.body(size: 10, color: AppTheme.muted)),
              Row(
                children: [
                  Icon(isOutgoing ? Icons.call_made : Icons.call_received, size: 12, color: AppTheme.greenDark),
                  const SizedBox(width: 4),
                  Text(duration, style: AppTheme.mono(size: 10, color: AppTheme.ink900)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
