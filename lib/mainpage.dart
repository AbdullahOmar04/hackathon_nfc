import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hackathon_nfc/Cards/view_cards.dart';
import 'package:hackathon_nfc/analytics.dart';
import 'package:hackathon_nfc/signing/login.dart';
import 'package:hackathon_nfc/nfc_payment.dart';
import 'package:http/http.dart' as http;

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selected = 0;
  String? _username;

  Future<List<Map<String, dynamic>>> _loadAccounts() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://jpcjofsdev.apigw-az-eu.webmethods.io/gateway/Accounts/v0.4.3/accounts',
        ),
        headers: {'x-customer-id': 'IND_CUST_015'},
      );

      if (response.statusCode != 200) return [];
      final data = json.decode(response.body);
      final List<dynamic> rawAccounts = data['data'] ?? [];

      return await Future.wait(
        rawAccounts.map((account) async {
          final issuer =
              account['institutionBasicInfo']?['name']?['enName'] ??
              'Unknown Bank';
          final iban = account['mainRoute']?['address'] ?? '';
          final accountId = account['accountId'] ?? account['id'] ?? '';
          double balance = 0;

          if (accountId.isNotEmpty) {
            final balResp = await http.get(
              Uri.parse(
                'https://jpcjofsdev.apigw-az-eu.webmethods.io/gateway/Balances/v0.4.3/accounts/$accountId/balances',
              ),
              headers: {'x-customer-id': 'IND_CUST_009'},
            );
            if (balResp.statusCode == 200) {
              final balData = json.decode(balResp.body);
              if (balData.containsKey('availableBalance')) {
                balance =
                    (balData['availableBalance']['balanceAmount'] ?? 0)
                        .toDouble();
              }
            }
          }

          return {
            'issuer': issuer,
            'iban': iban,
            'id': accountId,
            'balance': balance,
            'cliqAlias': account['cliqAlias'] ?? 'PJA',
          };
        }),
      );
    } catch (e) {
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    fetchUsername().then((name) {
      if (mounted) setState(() => _username = name);
    });
  }

  Future<void> _logout() async {
    if (!mounted) return;
    await FirebaseAuth.instance.signOut();
    // send them back to LoginPage
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  Future<String?> fetchUsername() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    final data = doc.data();
    if (data == null) return null;
    return data['username'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/logo.png',
          height: 120, // adjust as needed
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
          ),
        ),
      ),
      drawer: Drawer(
        backgroundColor: Theme.of(context).colorScheme.onPrimary,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: Text(
                  'Welcome, $_username',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_box),
                title: const Text('View Accounts'),
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ViewCardsPage()),
                    ),
              ),
              Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
      body:
          _selected == 0
              ? AnalyticsPage()
              : FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadAccounts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error loading accounts'));
                  } else {
                    final accounts = snapshot.data ?? [];
                    return NfcMoneyApp(userAccounts: accounts);
                  }
                },
              ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: (i) => setState(() => _selected = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.analytics), label: ''),
          NavigationDestination(icon: Icon(Icons.send), label: ''),
        ],
      ),
    );
  }
}
