import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';

class ClientForm extends StatefulWidget {
  const ClientForm({super.key, required this.db});
  final AppDatabase db;
  @override
  State<ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<ClientForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _rate = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty) return;
    await widget.db.addClient(
      name: _name.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      defaultRate: double.tryParse(_rate.text.trim()), // null if blank/garbage
    );
    _name.clear();
    _email.clear();
    _rate.clear();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _rate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Default Rate'),
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            FilledButton(onPressed: _add, child: const Text('Add')),
          ],
        ),
      ],
    ),
  );
}
