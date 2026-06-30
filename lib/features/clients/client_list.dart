import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';

class ClientList extends StatelessWidget {
  const ClientList({super.key, required this.clients});
  final List<Client> clients;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (final c in clients)
        ListTile(
          title: Text(c.name),
          subtitle: c.email == null ? null : Text(c.email!),
          trailing: c.defaultRate == null
              ? null
              : Text('\$${c.defaultRate!.toStringAsFixed(2)}/hr'),
        ),
    ],
  );
}
