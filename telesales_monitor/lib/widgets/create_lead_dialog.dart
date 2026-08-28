import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';
import '../models/lead_model.dart';

class CreateLeadDialog extends StatefulWidget {
  const CreateLeadDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CreateLeadDialog(),
    );
  }

  @override
  State<CreateLeadDialog> createState() => _CreateLeadDialogState();
}

class _CreateLeadDialogState extends State<CreateLeadDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  LeadStatus _selectedStatus = LeadStatus.interested;
  bool _isSaving = false;
  String? _phoneError;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _validatePhone(String value, TeleProvider tele) {
    final cleanDigits = value.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() {
      if (cleanDigits.isEmpty) {
        _phoneError = 'Phone number is required';
      } else if (cleanDigits.length < 10) {
        _phoneError = 'Phone number must have at least 10 digits (${cleanDigits.length}/10)';
      } else if (tele.isDuplicateLeadPhone(value)) {
        _phoneError = '⚠️ Warning: A lead with this phone number already exists';
      } else {
        _phoneError = null;
      }
    });
  }

  Future<void> _handleSaveLead(TeleProvider tele) async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final cleanDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter lead / client name', style: AppTheme.label(size: 11, color: AppTheme.white)),
          backgroundColor: AppTheme.orangePill,
        ),
      );
      return;
    }

    if (cleanDigits.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid 10-digit phone number', style: AppTheme.label(size: 11, color: AppTheme.white)),
          backgroundColor: AppTheme.orangePill,
        ),
      );
      return;
    }

    if (tele.isDuplicateLeadPhone(phone)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.ink900, width: 2),
          ),
          title: Text('Duplicate Phone Number', style: AppTheme.headline(size: 16, color: AppTheme.ink900)),
          content: Text(
            'A lead with phone number "$phone" is already in your database. Do you want to create a duplicate entry or update existing?',
            style: AppTheme.body(size: 13, color: AppTheme.ink800),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('CANCEL', style: AppTheme.label(size: 11, color: AppTheme.muted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.orangePill,
                foregroundColor: AppTheme.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('CREATE ANYWAY', style: AppTheme.label(size: 11, color: AppTheme.white)),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _isSaving = true);

    final success = await tele.saveContact(
      phoneNumber: phone,
      name: name,
      notes: _notesController.text.trim(),
    );

    // Update status if not default
    if (success && _selectedStatus != LeadStatus.interested) {
      final lead = tele.leads.cast<LeadModel?>().firstWhere(
        (l) => l?.phone == phone,
        orElse: () => null,
      );
      if (lead != null) {
        await tele.updateLeadStatus(lead.id, _selectedStatus);
      }
    }

    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '✓ New Lead "$name" verified & added!' : 'Failed to save lead',
            style: AppTheme.label(size: 11, color: AppTheme.ink900),
          ),
          backgroundColor: success ? AppTheme.greenNeon : AppTheme.orangePill,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.ink900, width: 2),
          boxShadow: AppTheme.neoShadow(color: AppTheme.ink900),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.greenNeon,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                        ),
                        child: const Icon(Icons.person_add_alt_1_rounded, size: 18, color: AppTheme.ink900),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('VERIFY & ADD LEAD', style: AppTheme.headline(size: 16, color: AppTheme.ink900)),
                          Text('Phone verification & duplicate check', style: AppTheme.label(size: 8.5, color: AppTheme.muted)),
                        ],
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close_rounded, size: 20, color: AppTheme.ink900),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Phone Number Input with Real-time Validation
              Text('PHONE NUMBER *', style: AppTheme.label(size: 9.5, color: AppTheme.ink900)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _phoneError != null
                        ? (_phoneError!.contains('Warning') ? AppTheme.orangePill : Colors.red)
                        : AppTheme.ink900,
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: AppTheme.mono(size: 14, color: AppTheme.ink900),
                  onChanged: (val) => _validatePhone(val, tele),
                  decoration: InputDecoration(
                    hintText: '+91 98765 43210',
                    hintStyle: AppTheme.mono(size: 12, color: AppTheme.muted),
                    prefixIcon: const Icon(Icons.phone_rounded, size: 18, color: AppTheme.ink900),
                    suffixIcon: _phoneController.text.isNotEmpty
                        ? (_phoneError == null
                            ? const Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.greenDark)
                            : Icon(
                                _phoneError!.contains('Warning') ? Icons.warning_amber_rounded : Icons.error_outline_rounded,
                                size: 20,
                                color: _phoneError!.contains('Warning') ? AppTheme.orangePill : Colors.red,
                              ))
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              if (_phoneError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _phoneError!,
                  style: AppTheme.label(
                    size: 8.5,
                    color: _phoneError!.contains('Warning') ? AppTheme.orangePill : Colors.red,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Contact Name Input
              Text('LEAD / CLIENT NAME *', style: AppTheme.label(size: 9.5, color: AppTheme.ink900)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                ),
                child: TextField(
                  controller: _nameController,
                  style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                  decoration: InputDecoration(
                    hintText: 'e.g. Rahul Sharma',
                    hintStyle: AppTheme.body(size: 12, color: AppTheme.muted),
                    prefixIcon: const Icon(Icons.person_rounded, size: 18, color: AppTheme.ink900),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Pipeline Stage Selector
              Text('PIPELINE STAGE', style: AppTheme.label(size: 9.5, color: AppTheme.ink900)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildStatusChip(LeadStatus.interested, 'INTERESTED'),
                  _buildStatusChip(LeadStatus.followUp, 'FOLLOW-UP'),
                  _buildStatusChip(LeadStatus.won, 'CONVERTED'),
                  _buildStatusChip(LeadStatus.notInterested, 'NOT INTERESTED'),
                ],
              ),
              const SizedBox(height: 12),

              // Notes / Requirements Input
              Text('NOTES / REQUIREMENTS', style: AppTheme.label(size: 9.5, color: AppTheme.ink900)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                ),
                child: TextField(
                  controller: _notesController,
                  maxLines: 2,
                  style: AppTheme.body(size: 12, color: AppTheme.ink900),
                  decoration: InputDecoration(
                    hintText: 'Add discussion notes, budget, call summary...',
                    hintStyle: AppTheme.body(size: 11, color: AppTheme.muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                        ),
                        child: Center(
                          child: Text('CANCEL', style: AppTheme.label(size: 10, color: AppTheme.ink900)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _isSaving ? null : () => _handleSaveLead(tele),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.greenNeon,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                          boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                        ),
                        child: Center(
                          child: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink900),
                                )
                              : Text('VERIFY & SAVE LEAD', style: AppTheme.label(size: 10, color: AppTheme.ink900)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(LeadStatus status, String label) {
    final isSelected = _selectedStatus == status;
    return GestureDetector(
      onTap: () => setState(() => _selectedStatus = status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.ink900 : AppTheme.paper,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.ink900, width: 1.2),
        ),
        child: Text(
          label,
          style: AppTheme.label(
            size: 8.5,
            color: isSelected ? AppTheme.limeYellow : AppTheme.ink900,
          ),
        ),
      ),
    );
  }
}
