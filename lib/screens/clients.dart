import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/widgets/content_app_bar.dart';
import 'package:time_tracker/widgets/content_body.dart';
import 'package:time_tracker/widgets/client_form.dart';
import 'package:time_tracker/widgets/client_list.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, required this.db});
  final AppDatabase db;
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  late final Stream<List<Client>> _clientsStream = widget.db.watchClients();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ContentAppBar(title: 'Clients', showBack: true),
    body: ContentBody(
      child: Column(
        children: [
          ClientForm(db: widget.db),
          Expanded(
            child: StreamBuilder<List<Client>>(
              stream: _clientsStream,
              builder: (context, snap) => ClientList(clients: snap.data ?? []),
            ),
          ),
        ],
      ),
    ),
  );
}
