import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';

class SimSetupScreen extends StatefulWidget {
  const SimSetupScreen({super.key});

  @override
  State<SimSetupScreen> createState() => _SimSetupScreenState();
}

class _SimSetupScreenState extends State<SimSetupScreen> {
  SimTrackingMode _selectedMode = SimTrackingMode.sim1Only;

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CALLYZER ENGINE · INITIAL SETUP',
                    style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.18),
                  ),
                  GestureDetector(
                    onTap: () => tele.fetchDeviceSims(),
                    child: Row(
                      children: [
                        const Icon(Icons.refresh, size: 14, color: AppTheme.greenDark),
                        const SizedBox(width: 4),
                        Text(
                          'RE-SCAN SIMs',
                          style: AppTheme.label(size: 9, color: AppTheme.greenDark, letterSpacing: 0.1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'AUTO-DETECTED\n',
                      style: AppTheme.headline(size: 38, color: AppTheme.ink900),
                    ),
                    TextSpan(
                      text: 'sim cards',
                      style: AppTheme.italicSerif(size: 36, color: AppTheme.greenDark),
                    ),
                    TextSpan(
                      text: '.',
                      style: AppTheme.headline(size: 38, color: AppTheme.greenNeon),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Select which SIM card should be monitored for telesales calls. Unselected personal SIM calls will be completely excluded from tracking.',
                style: AppTheme.body(size: 13, color: AppTheme.ink700),
              ),
              const SizedBox(height: 20),

              // Permissions Status Card
              NeoCard(
                backgroundColor: AppTheme.white,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'REQUIRED TELEPHONY PERMISSIONS',
                      style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.14),
                    ),
                    const SizedBox(height: 10),
                    const _PermissionRow(label: 'Call Log Access (READ_CALL_LOG)', isGranted: true),
                    const _PermissionRow(label: 'Phone State & SIM Detection (READ_PHONE_STATE)', isGranted: true),
                    const _PermissionRow(label: 'Contacts Identification (READ_CONTACTS)', isGranted: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Container(width: 8, height: 8, color: AppTheme.greenNeon),
                  const SizedBox(width: 8),
                  Text(
                    'DETECTED SIM SLOTS ON DEVICE',
                    style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (tele.isLoadingSims) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: AppTheme.greenNeon),
                  ),
                ),
              ] else ...[
                // Dynamic SIM 1 Card (from device)
                if (tele.detectedSims.isNotEmpty) ...[
                  _SimOptionCard(
                    title: 'SIM 1 · DETECTED',
                    carrierName: '${tele.detectedSims[0].displayName} (${tele.detectedSims[0].carrierName})',
                    description: tele.detectedSims[0].phoneNumber.isNotEmpty
                        ? 'Number: ${tele.detectedSims[0].phoneNumber}'
                        : 'Track all incoming & outgoing business calls on SIM Slot 1.',
                    isSelected: _selectedMode == SimTrackingMode.sim1Only,
                    onTap: () => setState(() => _selectedMode = SimTrackingMode.sim1Only),
                  ),
                  const SizedBox(height: 10),
                ],

                // Dynamic SIM 2 Card (from device if Dual SIM present)
                if (tele.detectedSims.length > 1) ...[
                  _SimOptionCard(
                    title: 'SIM 2 · DETECTED',
                    carrierName: '${tele.detectedSims[1].displayName} (${tele.detectedSims[1].carrierName})',
                    description: tele.detectedSims[1].phoneNumber.isNotEmpty
                        ? 'Number: ${tele.detectedSims[1].phoneNumber}'
                        : 'Track calls on SIM Slot 2.',
                    isSelected: _selectedMode == SimTrackingMode.sim2Only,
                    onTap: () => setState(() => _selectedMode = SimTrackingMode.sim2Only),
                  ),
                  const SizedBox(height: 10),
                ],

                // Track Both SIMs Option
                _SimOptionCard(
                  title: 'TRACK BOTH SIMs',
                  carrierName: 'All Detected SIM Slots',
                  description: 'Monitors every call across both SIM cards without filtering.',
                  isSelected: _selectedMode == SimTrackingMode.bothSims,
                  onTap: () => setState(() => _selectedMode = SimTrackingMode.bothSims),
                ),
              ],
              const SizedBox(height: 28),

              // Start Tracking Button
              NeoButton.accent(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'CONFIRM & START TRACKING →',
                    style: AppTheme.label(size: 12, color: AppTheme.ink900, letterSpacing: 0.14),
                  ),
                ),
                onTap: () {
                  tele.completeSetup(mode: _selectedMode);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimOptionCard extends StatelessWidget {
  final String title;
  final String carrierName;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _SimOptionCard({
    required this.title,
    required this.carrierName,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return NeoCard(
      backgroundColor: isSelected ? AppTheme.ink900 : AppTheme.white,
      shadowColor: isSelected ? AppTheme.greenNeon : AppTheme.ink900,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTheme.label(
                  size: 9,
                  color: isSelected ? AppTheme.limeYellow : AppTheme.greenDark,
                  letterSpacing: 0.14,
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppTheme.greenNeon : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppTheme.greenNeon : AppTheme.ink900,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: AppTheme.ink900)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            carrierName,
            style: AppTheme.headline(
              size: 20,
              color: isSelected ? AppTheme.white : AppTheme.ink900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: AppTheme.body(
              size: 11,
              color: isSelected ? AppTheme.lightMuted : AppTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String label;
  final bool isGranted;

  const _PermissionRow({required this.label, required this.isGranted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isGranted ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isGranted ? AppTheme.greenDark : AppTheme.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(size: 11, color: AppTheme.ink700),
            ),
          ),
        ],
      ),
    );
  }
}
