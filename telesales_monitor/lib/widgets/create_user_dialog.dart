import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';

class CreateUserDialog extends StatefulWidget {
  const CreateUserDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CreateUserDialog(),
    );
  }

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController(text: '123456');
  final _targetCtrl = TextEditingController(text: '100');

  String _selectedRole = 'caller';
  String _selectedTeam = 'Telesales Team';
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleCreateUser(TeleProvider tele) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final res = await tele.createUser(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim().isNotEmpty
          ? _emailCtrl.text.trim()
          : '${_nameCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '')}@askeva.com',
      phone: _phoneCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
      role: _selectedRole,
      team: _selectedTeam,
      dailyTarget: int.tryParse(_targetCtrl.text.trim()) ?? 100,
    );

    setState(() => _isLoading = false);

    if (mounted) {
      if (res['success'] == true) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ User "${_nameCtrl.text.trim()}" created successfully!',
              style: AppTheme.label(size: 11, color: AppTheme.ink900),
            ),
            backgroundColor: AppTheme.greenNeon,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message'] ?? 'Failed to create user',
              style: AppTheme.label(size: 11, color: AppTheme.white),
            ),
            backgroundColor: AppTheme.orangePill,
          ),
        );
      }
    }
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
          child: Form(
            key: _formKey,
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
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.ink900, width: 1.5),
                          ),
                          child: const Icon(Icons.person_add_rounded, size: 20, color: AppTheme.ink900),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CREATE USER', style: AppTheme.headline(size: 16)),
                            Text('Add new agent or caller to team', style: AppTheme.mono(size: 10, color: AppTheme.muted)),
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

                // Full Name
                Text('FULL NAME *', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                  decoration: InputDecoration(
                    hintText: 'e.g. Karthik',
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
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),

                // Phone Number
                Text('PHONE NUMBER *', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                  decoration: InputDecoration(
                    hintText: 'e.g. 9876543210',
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
                  ),
                  validator: (v) => (v == null || v.trim().length < 6) ? 'Valid phone number required' : null,
                ),
                const SizedBox(height: 12),

                // Email Address
                Text('EMAIL ADDRESS (OPTIONAL)', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: AppTheme.body(size: 13, color: AppTheme.ink900),
                  decoration: InputDecoration(
                    hintText: 'e.g. karthik@askeva.com',
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
                  ),
                ),
                const SizedBox(height: 12),

                // Password
                Text('LOGIN PASSWORD *', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                  decoration: InputDecoration(
                    hintText: 'Password (e.g. 123456)',
                    hintStyle: AppTheme.body(size: 12, color: AppTheme.muted),
                    filled: true,
                    fillColor: AppTheme.paper,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: AppTheme.ink900,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.ink900, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.ink900, width: 1.5),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Password is required' : null,
                ),
                const SizedBox(height: 14),

                // Role Selector (CALLER vs MANAGER)
                Text('ASSIGN ROLE', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedRole = 'caller'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedRole == 'caller' ? AppTheme.greenNeon : AppTheme.paper,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.ink900, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              '📱 CALLER AGENT',
                              style: AppTheme.label(size: 9.5, color: AppTheme.ink900),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedRole = 'manager'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedRole == 'manager' ? AppTheme.limeYellow : AppTheme.paper,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.ink900, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              '👔 ADMIN / MANAGER',
                              style: AppTheme.label(size: 9.5, color: AppTheme.ink900),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Team Selection
                Text('ASSIGN TEAM', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTeam,
                      isExpanded: true,
                      dropdownColor: AppTheme.paper,
                      style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900),
                      items: ['Telesales Team', 'Inbound Support', 'Outbound Sales', 'VIP Accounts'].map((t) {
                        return DropdownMenuItem(value: t, child: Text('🏢 $t'));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedTeam = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Daily Target
                Text('DAILY CALL TARGET', style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.1)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _targetCtrl,
                  keyboardType: TextInputType.number,
                  style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                  decoration: InputDecoration(
                    hintText: '100 calls',
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
                  ),
                ),
                const SizedBox(height: 20),

                // Submit Button
                GestureDetector(
                  onTap: _isLoading ? null : () => _handleCreateUser(tele),
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
                        _isLoading ? 'CREATING USER...' : 'CREATE USER & ADD TO TEAM',
                        style: AppTheme.label(size: 12, color: AppTheme.ink900, letterSpacing: 0.1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
