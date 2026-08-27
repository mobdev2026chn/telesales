import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';

class SaveContactDialog extends StatefulWidget {
  final String phoneNumber;
  final String? initialName;

  const SaveContactDialog({
    super.key,
    required this.phoneNumber,
    this.initialName,
  });

  static Future<void> show(BuildContext context, String phoneNumber, {String? initialName}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => SaveContactDialog(
        phoneNumber: phoneNumber,
        initialName: initialName,
      ),
    );
  }

  @override
  State<SaveContactDialog> createState() => _SaveContactDialogState();
}

class _SaveContactDialogState extends State<SaveContactDialog> {
  late TextEditingController _nameController;
  late TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final name = (widget.initialName != null &&
            widget.initialName != widget.phoneNumber &&
            widget.initialName != 'Unknown')
        ? widget.initialName!
        : '';
    _nameController = TextEditingController(text: name);
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveToCRM(TeleProvider tele) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a contact name', style: AppTheme.label(size: 11, color: AppTheme.white)),
          backgroundColor: AppTheme.orangePill,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final success = await tele.saveContact(
      phoneNumber: widget.phoneNumber,
      name: name,
      notes: _notesController.text.trim(),
    );
    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '✓ Contact "$name" saved successfully!' : 'Failed to save contact',
            style: AppTheme.label(size: 11, color: AppTheme.ink900),
          ),
          backgroundColor: success ? AppTheme.greenNeon : AppTheme.orangePill,
        ),
      );
    }
  }

  void _handleSaveToPhone(TeleProvider tele) {
    final name = _nameController.text.trim();
    tele.openNativePhoneContactEditor(widget.phoneNumber, name);
    _handleSaveToCRM(tele);
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);

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
                          color: AppTheme.limeYellow,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                        ),
                        child: const Icon(Icons.person_add_alt_1_rounded, size: 20, color: AppTheme.ink900),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SAVE CONTACT', style: AppTheme.headline(size: 16)),
                          Text(widget.phoneNumber, style: AppTheme.mono(size: 11, color: AppTheme.muted)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppTheme.ink900),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.paper, thickness: 1.5),
              const SizedBox(height: 12),

              // Contact Name Field
              Text('CONTACT / CLIENT NAME', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                autofocus: true,
                style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900),
                decoration: InputDecoration(
                  hintText: 'e.g. Rajesh Kumar (Client)',
                  hintStyle: AppTheme.body(size: 13, color: AppTheme.muted),
                  filled: true,
                  fillColor: AppTheme.paper,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.ink900, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.ink900, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.greenDark, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Notes / Company Field
              Text('NOTES / COMPANY (OPTIONAL)', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
              const SizedBox(height: 6),
              TextField(
                controller: _notesController,
                style: AppTheme.body(size: 13, color: AppTheme.ink900),
                decoration: InputDecoration(
                  hintText: 'e.g. Interested in enterprise plan',
                  hintStyle: AppTheme.body(size: 12, color: AppTheme.muted),
                  filled: true,
                  fillColor: AppTheme.paper,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.ink900, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.ink900, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.greenDark, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Save to CRM Button
              GestureDetector(
                onTap: _isSaving ? null : () => _handleSaveToCRM(tele),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.greenNeon,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.ink900, width: 2),
                    boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                  ),
                  child: Center(
                    child: Text(
                      _isSaving ? 'SAVING...' : 'SAVE CONTACT TO CRM',
                      style: AppTheme.label(size: 12, color: AppTheme.ink900, letterSpacing: 0.1),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Save to Phone Contacts Button
              GestureDetector(
                onTap: _isSaving ? null : () => _handleSaveToPhone(tele),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.paper,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.contacts_rounded, size: 16, color: AppTheme.ink900),
                      const SizedBox(width: 6),
                      Text(
                        'Save to Mobile Phone Book 📲',
                        style: AppTheme.label(size: 11, color: AppTheme.ink900),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
