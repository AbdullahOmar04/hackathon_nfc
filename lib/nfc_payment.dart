// ignore_for_file: avoid_print, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:uuid/uuid.dart';

/// ───────────────────────────────────────────────────────────────
/// Replace these with your real values:
/// ───────────────────────────────────────────────────────────────
const String baseUrl =
    'https://jpcjofsdev.apigw-az-eu.webmethods.io/gateway/RFC%20-%20Payment%20Initiation%20Services%20%28PIS%29/v0.4.3';
const String bearerToken = 'YOUR_BEARER_TOKEN';
const String currentUserCliqAlias = 'PJA';
const String jwsSignature = 'YOUR_JWS_SIGNATURE';
const String financialInstitutionId = 'JORDJOA0'; // BIC code
const String customerUserId = 'YOUR_CUSTOMER_ID';
const String customerUserAgent = 'YourApp/1.0';

class NfcMoneyApp extends StatefulWidget {
  final List<Map<String, dynamic>> userAccounts;
  const NfcMoneyApp({super.key, required this.userAccounts});

  @override
  // ignore: library_private_types_in_public_api
  _NfcMoneyAppState createState() => _NfcMoneyAppState();
}

class _NfcMoneyAppState extends State<NfcMoneyApp> {
  final MethodChannel _hceChan = MethodChannel('hackathon_nfc/hce');
  bool _isPaymentMode = false;
  bool _isProcessing = false;
  String _status = 'Ready';
  final TextEditingController _amountCtrl = TextEditingController(text: '5.00');
  final _uuid = Uuid();

  // Store user accounts
  List<Map<String, dynamic>> _userAccounts = [];
  Map<String, dynamic>? _selectedAccount;
  Map<String, dynamic>? _selectedReceiverAccount; // For sharing alias
  StreamSubscription<QuerySnapshot>? _receiverListener;

  // Store resolved account information
  Map<String, dynamic>? _resolvedAccountInfo;

  // Timer for payment listening
  Timer? _paymentListenerTimer;

  // Store payment initiation response for status checking
  // ignore: unused_field
  Map<String, dynamic>? _paymentInitiationResponse;

  static final Uint8List selectApdu = Uint8List.fromList([
    0x00, 0xA4, 0x04, 0x00, 0x07, // CLA INS P1 P2 Lc
    0xF0, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, // AID bytes
  ]);

  @override
  void initState() {
    super.initState();
    _checkNfcAvailability();
    _userAccounts = widget.userAccounts;
    _selectedAccount = _userAccounts.isNotEmpty ? _userAccounts.first : null;
    _selectedReceiverAccount =
        _userAccounts.isNotEmpty ? _userAccounts.first : null;
  }

  Future<void> _checkNfcAvailability() async {
    final available = await NfcManager.instance.isAvailable();
    setState(() {
      _status = available ? 'NFC is available' : 'NFC not available';
    });
  }

  Future<Map<String, dynamic>?> _checkPaymentStatus(
    String messageId,
    String instructionId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/PIS/initiation/$messageId/$instructionId'),
        headers: {
          'Authorization': 'Bearer $bearerToken',
          'Accept': 'application/json',
          'x-interactions-id': _uuid.v4(),
          'x-idempotency-key': _uuid.v4(),
          'x-financial-id': financialInstitutionId,
          'x-jws-signature': jwsSignature,
          'x-auth-date': DateTime.now().toUtc().toIso8601String(),
          'x-customer-id': customerUserId,
          'x-customer-ip-address': '127.0.0.1',
          'x-customer-user-agent': customerUserAgent,
          'instructionId': instructionId,
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        print(
          'Payment status check failed (${response.statusCode}): ${response.body}',
        );
        return null;
      }
    } catch (e) {
      print('Error checking payment status: $e');
      return null;
    }
  }

  void _startReceiverListener(String alias) {
    _receiverListener = FirebaseFirestore.instance
        .collection('payments')
        .where('fromAlias', isEqualTo: alias)
        .where('notified', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final fromAlias = data['fromAlias'];
            final amount = data['amount'];

            // Show popup
            _showReceiverPopup(fromAlias, amount);

            // Mark as notified so we don't show again
            doc.reference.update({'notified': true});
          }
        });

    // Stop listening after 2 minutes
    Future.delayed(const Duration(minutes: 2), () {
      _receiverListener?.cancel();
    });
  }

  void _showReceiverPopup(String fromAlias, dynamic amountRaw) {
    final amount =
        (amountRaw is int)
            ? amountRaw.toDouble()
            : (amountRaw is double ? amountRaw : 0.0);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            contentPadding: const EdgeInsets.all(20),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '💰 Payment Received!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_downward, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        '${amount.toStringAsFixed(2)} JOD',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildDetailRow('From:', fromAlias),
                _buildDetailRow(
                  'Date:',
                  DateTime.now().toString().split('.')[0],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Funds have been received successfully and added to your balance.',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label ',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startListeningForPayment() async {
    if (_selectedReceiverAccount == null) {
      setState(() => _status = 'Please select a receiver account first');
      return;
    }
    _startReceiverListener(currentUserCliqAlias);

    final aliasToListenFor = _selectedReceiverAccount!['cliqAlias'];

    // Listen for incoming payments on the selected account's alias
    setState(() {
      _status = 'Listening for incoming payments on $aliasToListenFor...';
    });

    _paymentListenerTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        final response = await http.get(
          Uri.parse('$baseUrl/PIS/status/$aliasToListenFor'),
          headers: {
            'Authorization': 'Bearer $bearerToken',
            'Accept': 'application/json',
            'x-financial-id': financialInstitutionId,
            'x-customer-id': customerUserId,
          },
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body);

          // Check if payment is completed
          if (data['status'] == 'COMPLETED') {
            timer.cancel();

            // Show confirmation dialog for received payment to the RECEIVER
            if (mounted) {
              setState(() {
                _status = 'Payment received successfully!';
              });

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                  return AlertDialog(
                    icon: Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 48,
                    ),
                    title: Text('💰 Payment Received!'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.account_balance_wallet,
                                color: Colors.green,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '${data['amount']?.toStringAsFixed(2) ?? '0.00'} JOD',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                        _buildPaymentDetailRow(
                          'From:',
                          data['senderName'] ?? 'Unknown',
                        ),
                        _buildPaymentDetailRow(
                          'To Account:',
                          _selectedReceiverAccount!['iban'],
                        ),
                        _buildPaymentDetailRow(
                          'Transaction ID:',
                          data['transactionId'] ?? 'N/A',
                        ),
                        _buildPaymentDetailRow(
                          'Date:',
                          DateTime.now().toString().split('.')[0],
                        ),
                        SizedBox(height: 16),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.blue,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'The amount has been successfully transferred to your account.',
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _status = 'Ready for next transaction';
                          });
                        },
                        child: Text('OK'),
                      ),
                    ],
                  );
                },
              );
            }
          } else if (data['status'] == 'PENDING') {
            // Update status to show payment is being processed
            setState(() {
              _status = 'Payment processing... Please wait.';
            });
          }
        }
      } catch (e) {
        print('Error checking payment status: $e');
        // Don't show error to user for polling errors, just log them
      }
    });

    // Cancel the timer after 2 minutes if no payment is received
    Future.delayed(Duration(minutes: 2), () {
      if (_paymentListenerTimer?.isActive == true) {
        _paymentListenerTimer?.cancel();
        if (mounted) {
          setState(
            () => _status = 'Payment listening timeout. Please try again.',
          );
        }
      }
    });
  }

  Widget _buildPaymentDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startSendSession() async {
    if (_isProcessing) return;

    if (_selectedReceiverAccount == null) {
      setState(() => _status = 'Please select a receiver account first');
      return;
    }
    _startReceiverListener(currentUserCliqAlias);

    setState(() => _isProcessing = true);

    try {
      final aliasToShare = _selectedReceiverAccount!['cliqAlias'];

      await _hceChan.invokeMethod('setHcePayload', {'payload': aliasToShare});
      setState(() {
        _status = 'Ready to share alias "$aliasToShare"\nHold near receiver…';
      });

      // Start listening for payments when sharing alias
      _startListeningForPayment();

      Future.delayed(Duration(seconds: 30), () {
        if (mounted && _status.contains('Ready to share alias')) {
          setState(() => _status = 'Share session timed out');
          _paymentListenerTimer?.cancel();
        }
      });
    } catch (e) {
      setState(() => _status = 'Error preparing alias: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _startPaymentStatusMonitoring(
    Map<String, dynamic> paymentResponse,
  ) async {
    if (paymentResponse['messageId'] == null ||
        paymentResponse['instructionId'] == null) {
      print('Missing messageId or instructionId in payment response');
      return;
    }

    final messageId = paymentResponse['messageId'];
    final instructionId = paymentResponse['instructionId'];

    setState(() {
      _status = 'Monitoring payment status...';
    });

    // Monitor payment status every 3 seconds
    Timer.periodic(Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        final statusResponse = await _checkPaymentStatus(
          messageId,
          instructionId,
        );

        if (statusResponse != null) {
          final status = statusResponse['status'];
          final statusDateTime = statusResponse['statusDateTime'];

          setState(() {
            _status = 'Payment Status: $status';
            if (statusDateTime != null) {
              _status += '\nLast Updated: $statusDateTime';
            }
          });

          // Check if payment is completed or failed
          if (status == 'COMPLETED' || status == 'ACSP' || status == 'ACSC') {
            timer.cancel();

            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                  return AlertDialog(
                    icon: Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 48,
                    ),
                    title: Text('🎉 Payment Completed!'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.done_all, color: Colors.green),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your payment has been successfully processed and completed.',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                        _buildPaymentDetailRow('Status:', status),
                        _buildPaymentDetailRow('Message ID:', messageId),
                        _buildPaymentDetailRow(
                          'Instruction ID:',
                          instructionId,
                        ),
                        if (statusDateTime != null)
                          _buildPaymentDetailRow('Completed:', statusDateTime),
                        if (statusResponse['reasonCode'] != null)
                          _buildPaymentDetailRow(
                            'Reason Code:',
                            statusResponse['reasonCode'],
                          ),
                        if (statusResponse['reasonDescription'] != null)
                          _buildPaymentDetailRow(
                            'Description:',
                            statusResponse['reasonDescription'],
                          ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _resolvedAccountInfo = null;
                            _paymentInitiationResponse = null;
                            _status = 'Ready for next transaction';
                          });
                        },
                        child: Text('OK'),
                      ),
                    ],
                  );
                },
              );
            }
          } else if (status == 'RJCT' || status == 'CANC') {
            timer.cancel();

            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                  return AlertDialog(
                    icon: Icon(Icons.error, color: Colors.red, size: 48),
                    title: Text(
                      '❌ Payment ${status == 'RJCT' ? 'Rejected' : 'Cancelled'}',
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your payment was ${status == 'RJCT' ? 'rejected' : 'cancelled'}.',
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                        _buildPaymentDetailRow('Status:', status),
                        _buildPaymentDetailRow('Message ID:', messageId),
                        _buildPaymentDetailRow(
                          'Instruction ID:',
                          instructionId,
                        ),
                        if (statusDateTime != null)
                          _buildPaymentDetailRow(
                            'Status Date:',
                            statusDateTime,
                          ),
                        if (statusResponse['reasonCode'] != null)
                          _buildPaymentDetailRow(
                            'Reason Code:',
                            statusResponse['reasonCode'],
                          ),
                        if (statusResponse['reasonDescription'] != null)
                          _buildPaymentDetailRow(
                            'Description:',
                            statusResponse['reasonDescription'],
                          ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _resolvedAccountInfo = null;
                            _paymentInitiationResponse = null;
                            _status = 'Ready for next transaction';
                          });
                        },
                        child: Text('OK'),
                      ),
                    ],
                  );
                },
              );
            }
          }
        }
      } catch (e) {
        print('Error monitoring payment status: $e');
      }
    });

    // Stop monitoring after 5 minutes
    Future.delayed(Duration(minutes: 5), () {
      if (mounted) {
        setState(() {
          _status = 'Payment status monitoring timeout. Please check manually.';
        });
      }
    });
  }

  Future<void> _startReceiveSession() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _status = 'Waiting for NFC tap…';
      _resolvedAccountInfo = null;
    });

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (tag) async {
          final iso = IsoDepAndroid.from(tag);
          if (iso == null) {
            setState(() => _status = 'Incompatible NFC tag');
            return;
          }

          try {
            final resp = await iso.transceive(selectApdu);

            if (resp.length < 2) {
              setState(
                () => _status = 'Response too short: ${resp.length} bytes',
              );
              return;
            }

            final sw1 = resp[resp.length - 2];
            final sw2 = resp[resp.length - 1];
            if (sw1 != 0x90 || sw2 != 0x00) {
              setState(
                () =>
                    _status =
                        'Tag error: SW1=${sw1.toRadixString(16)}, SW2=${sw2.toRadixString(16)}',
              );
              return;
            }

            final payload = resp.sublist(0, resp.length - 2);
            if (payload.length < 2 || payload[0] != 0x03) {
              setState(
                () =>
                    _status = 'Invalid payload format: ${payload.length} bytes',
              );
              return;
            }

            final aliasLength = payload[1];
            if (payload.length < 2 + aliasLength) {
              setState(() => _status = 'Payload too short for declared length');
              return;
            }

            final aliasBytes = payload.sublist(2, 2 + aliasLength);
            final senderAlias = utf8.decode(aliasBytes);

            setState(() => _status = 'Resolving proxy for $senderAlias…');

            // Build resolve request
            final resolveBody = {
              "endToEnd": "123DK",
              "papcProxyService":
                  "{local/crossborder}.{ProxyProvider}.{ServiceName}",
              "papcPurpose": "payment initiation services",
              "papcResolveDetails": {
                "papcRoute": {"schema": "CLIQ", "address": senderAlias},
                "additionalInfo": [
                  {"value": "JOD", "key": "currency"},
                ],
                "servicerIdentification": {
                  "schema": "bicCode",
                  "address": financialInstitutionId,
                },
                "papcAuth": [
                  {"value": "1234", "key": "NID"},
                ],
              },
              "papcServiceType": "resolve",
            };

            // Send resolve
            final papcUrl = Uri.parse('$baseUrl/PaPC/resolve');
            final papcResponse = await http.post(
              papcUrl,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $bearerToken',
                'Accept': 'application/json',
                'x-interactions-id': _uuid.v4(),
                'x-idempotency-key': _uuid.v4(),
                'x-financial-id': financialInstitutionId,
                'x-jws-signature': jwsSignature,
                'x-customer-id': customerUserId,
                'x-customer-user-agent': customerUserAgent,
                'x-auth-date': DateTime.now().toUtc().toIso8601String(),
                'x-customer-ip-address': '127.0.0.1',
              },
              body: jsonEncode(resolveBody),
            );

            if (papcResponse.statusCode < 200 ||
                papcResponse.statusCode >= 300) {
              throw Exception(
                'Proxy resolve failed (${papcResponse.statusCode}): ${papcResponse.body}',
              );
            }

            final papcJson = jsonDecode(papcResponse.body);

            setState(() {
              _resolvedAccountInfo = papcJson;
              _status = '✅ Account resolved successfully!';
            });
          } catch (e) {
            setState(() => _status = 'Error: $e');
          } finally {
            await NfcManager.instance.stopSession();
            setState(() => _isProcessing = false);
          }
        },
      );
    } catch (e) {
      setState(() {
        _status = 'Session start error: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _initiatePayment() async {
    if (_resolvedAccountInfo == null || _selectedAccount == null) {
      setState(() => _status = 'Please select an account first');
      return;
    }

    final balance = _selectedAccount!['balance'] as double;
    final amount = double.parse(_amountCtrl.text);
    if (amount > balance) {
      setState(() => _status = 'Insufficient funds in selected account');
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = 'Initiating payment...';
    });

    try {
      final amount = double.parse(_amountCtrl.text);
      final papcResultDetails = _resolvedAccountInfo!['papcResultDetails'];
      final accountRoute = papcResultDetails['accountRoute'];
      final name = papcResultDetails['name'];
      final servicerIdentification =
          papcResultDetails['servicerIdentification'];

      final paymentBody = {
        "groupHeader": {
          "batchBooking": "true",
          "batchPurpose": "111121140",
          "creationDateTime": DateTime.now().toUtc().toIso8601String(),
          "numberOfTrx": "1",
          "paymentMethod": "DOMESTIC.CLIQ",
          "totalTrxAmount": {"amount": amount, "currency": "JOD"},
        },
        "instructionsInfo": [
          {
            "accounts": [
              {
                "accountAgentParty": "cdtrAgt",
                "accountType": "cdtrAgtAcct",
                "mainRoute": {
                  "schema": accountRoute['schema'],
                  "address": accountRoute['address'],
                },
              },
            ],
            "agents": [
              {
                "agent": {
                  "enName": name['enName'],
                  "agentIdentification": {
                    "schema": servicerIdentification['schema'],
                    "address": servicerIdentification['address'],
                  },
                },
                "agentType": "cdtrAgt",
              },
            ],
            "categoryPurpose": "111121140",
            "clearingChannel": "RTGS",
            "identifications": {
              "endToEnd": _resolvedAccountInfo!['endToEnd'],
              "trxId": _uuid.v4(),
            },
            "involvedParties": [
              {
                "involvedParty": {"enName": name['enName']},
                "involvedPartyType": "cdtr",
              },
            ],
            "localInstrument": "CSDC",
            "remittanceInformation": {
              "unstructured": ["NFC P2P Payment"],
            },
            "serviceLevel": "3",
            "supplementaryData": [
              {"key": "paymentSource", "value": "NFC_P2P"},
            ],
            "trxAmount": {"amount": amount, "currency": "JOD"},
            "trxPresDateTime": DateTime.now().toUtc().toIso8601String(),
          },
        ],
      };

      final response = await http.post(
        Uri.parse('$baseUrl/PIS/initiation'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearerToken',
          'Accept': 'application/json',
          'x-interactions-id': _uuid.v4(),
          'x-idempotency-key': _uuid.v4(),
          'x-financial-id': financialInstitutionId,
          'x-jws-signature': jwsSignature,
          'x-customer-id': customerUserId,
          'x-customer-user-agent': customerUserAgent,
          'x-auth-date': DateTime.now().toUtc().toIso8601String(),
          'x-customer-ip-address': '127.0.0.1',
        },
        body: jsonEncode(paymentBody),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = jsonDecode(response.body);
        setState(() => _status = '✅ Payment initiated successfully!');

        // Store payment initiation response for status checking
        _paymentInitiationResponse = responseData;

        // Start monitoring payment status
        _startPaymentStatusMonitoring(responseData);

        // Show confirmation dialog for SENDER
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                icon: Icon(Icons.check_circle, color: Colors.green, size: 48),
                title: Text('💸 Payment Sent!'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.send, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(
                            '${amount.toStringAsFixed(2)} JOD',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildPaymentDetailRow('To:', name['enName'] ?? 'Unknown'),
                    _buildPaymentDetailRow(
                      'Message ID:',
                      responseData['messageId'] ?? 'N/A',
                    ),
                    _buildPaymentDetailRow(
                      'Instruction ID:',
                      responseData['instructionId'] ?? 'N/A',
                    ),
                    _buildPaymentDetailRow(
                      'Date:',
                      DateTime.now().toString().split('.')[0],
                    ),
                    SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.green,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Payment has been successfully sent and is being processed.',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _resolvedAccountInfo = null;
                        _status = 'Ready for next transaction';
                      });
                    },
                    child: Text('OK'),
                  ),
                ],
              );
            },
          );
        }
        try {
          await FirebaseFirestore.instance.collection('payments').add({
            'fromAlias': currentUserCliqAlias,
            'toAlias':
                name['enName'], // or _selectedReceiverAccount?['cliqAlias']
            'amount': amount,
            'timestamp': FieldValue.serverTimestamp(),
            'notified': false,
          });
          print('✅ Firestore payment added');
        } catch (e) {
          print('❌ Failed to add payment to Firestore: $e');
        }
      } else {
        throw Exception(
          'Payment initiation failed (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      setState(() => _status = '❌ Payment error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Widget _buildAccountInfoCard() {
    if (_resolvedAccountInfo == null) return SizedBox.shrink();

    final papcResultDetails = _resolvedAccountInfo!['papcResultDetails'];
    final accountRoute = papcResultDetails['accountRoute'];
    final name = papcResultDetails['name'];
    final address = papcResultDetails['address'];
    final servicerIdentification = papcResultDetails['servicerIdentification'];

    return Card(
      elevation: 4,
      margin: EdgeInsets.only(top: 20),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance, color: Colors.green, size: 24),
                SizedBox(width: 8),
                Text(
                  'Account Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // IBAN
            _buildInfoRow('IBAN', accountRoute['address']),

            // Account Schema
            _buildInfoRow('Account Schema', accountRoute['schema']),

            // Account Holder Name
            _buildInfoRow('Account Holder (EN)', name['enName']),
            _buildInfoRow('Account Holder (AR)', name['arName']),

            // Trading Name if available
            if (name['tradeName'] != null) ...[
              _buildInfoRow('Trading Name (EN)', name['tradeName']['enName']),
              _buildInfoRow('Trading Name (AR)', name['tradeName']['arName']),
            ],

            // Bank Information
            _buildInfoRow('Bank BIC', servicerIdentification['address']),
            _buildInfoRow('Bank Schema', servicerIdentification['schema']),

            // Address
            Divider(),
            Text(
              'Address:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text('${address['city']}, ${address['state']}'),
            Text(
              '${address['countryInfo']['countryName']} (${address['countryInfo']['countryCode']})',
            ),
            Text('Postcode: ${address['postcode']}'),

            // Address lines
            if (address['addresslines'] != null) ...[
              SizedBox(height: 8),
              ...((address['addresslines'] as List).map(
                (line) => Text(line.toString()),
              )),
            ],

            // Additional Info
            if (papcResultDetails['additionalInfo'] != null) ...[
              Divider(),
              Text(
                'Additional Information:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              ...((papcResultDetails['additionalInfo'] as List).map(
                (info) => Text('${info['key']}: ${info['value']}'),
              )),
            ],

            // Transaction Details
            Divider(),
            _buildInfoRow('End to End ID', _resolvedAccountInfo!['endToEnd']),
            _buildInfoRow('UUID', _resolvedAccountInfo!['UUID']),
            _buildInfoRow('Timestamp', _resolvedAccountInfo!['timestamp']),
            _buildInfoRow('Result', _resolvedAccountInfo!['totalResult']),

            // Payment Button
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _initiatePayment,
              icon: Icon(_isProcessing ? Icons.hourglass_empty : Icons.payment),
              label: Text(_isProcessing ? 'Processing...' : 'Initiate Payment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                textStyle: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
          Expanded(
            child: SelectableText(
              value ?? 'N/A',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        'P2P NFC + Cliq Pay',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
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
      actions: [
        IconButton(
          icon: Icon(
            _isPaymentMode ? Icons.swap_horiz : Icons.nfc,
            color: Colors.white,
          ),
          tooltip:
              _isPaymentMode ? 'Switch to Share Alias' : 'Switch to Send Money',
          onPressed:
              _isProcessing
                  ? null
                  : () => setState(() => _isPaymentMode = !_isPaymentMode),
        ),
      ],
    ),
    body: ListView(
      padding: EdgeInsets.all(24),
      children: [
        Card(
          elevation: 4,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(
                  _isPaymentMode ? Icons.payment : Icons.nfc,
                  size: 48,
                  color: Colors.indigo,
                ),
                SizedBox(height: 16),
                Text(
                  _isPaymentMode ? 'Send Payment' : 'Share Your Alias',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                if (_isPaymentMode) ...[
                  SizedBox(height: 16),
                  // Sender Account Dropdown
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, dynamic>>(
                        isExpanded: true,
                        value: _selectedAccount,
                        hint: Text('Select Account'),
                        items:
                            _userAccounts.map((account) {
                              final idx = _userAccounts.indexOf(account);
                              final bankName =
                                  idx == 0
                                      ? 'Capital Bank'
                                      : idx == 1
                                      ? 'Housing Bank'
                                      : idx == 2
                                      ? 'Jordan Kuwait Bank'
                                      : account['issuer'];
                              final balance =
                                  idx == 0
                                      ? '12,450.75'
                                      : idx == 1
                                      ? '8,234.20'
                                      : idx == 2
                                      ? '15,680.40'
                                      : account['balance'].toStringAsFixed(2);
                              return DropdownMenuItem<Map<String, dynamic>>(
                                value: account,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        bankName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        'Balance: $balance JOD',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                        onChanged:
                            (account) =>
                                setState(() => _selectedAccount = account),
                      ),
                    ),
                  ),

                  SizedBox(height: 16),
                  // Amount Field
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount (JOD)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                      helperText: 'Enter amount to send',
                    ),
                    enabled: !_isProcessing,
                  ),
                ] else ...[
                  SizedBox(height: 16),
                  // Receiver Dropdown for Sharing Alias
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, dynamic>>(
                        isExpanded: true,
                        value: _selectedReceiverAccount,
                        hint: Text('Select Receiver Account'),
                        items:
                            _userAccounts.map((account) {
                              return DropdownMenuItem<Map<String, dynamic>>(
                                value: account,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _userAccounts.indexOf(account) == 0
                                            ? 'Capital Bank'
                                            : _userAccounts.indexOf(account) ==
                                                1
                                            ? 'Housing Bank'
                                            : _userAccounts.indexOf(account) ==
                                                2
                                            ? 'Jordan Kuwait Bank'
                                            : account['issuer'],
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),

                                      Text(
                                        'Alias: ${account['cliqAlias']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                        onChanged: (account) {
                          setState(() => _selectedReceiverAccount = account);
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        SizedBox(height: 20),

        ElevatedButton.icon(
          onPressed:
              _isProcessing
                  ? null
                  : (_isPaymentMode ? _startReceiveSession : _startSendSession),
          icon: Icon(
            _isProcessing
                ? Icons.hourglass_empty
                : (_isPaymentMode ? Icons.contactless : Icons.nfc),
          ),
          label: Text(
            _isProcessing
                ? 'Processing…'
                : (_isPaymentMode
                    ? 'Tap to Send Payment'
                    : 'Share Alias via NFC'),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),

        if (_isPaymentMode) ...[
          SizedBox(height: 20),
          Text(
            'Instructions:\n'
            '1. Enter the amount you want to send\n'
            '2. Tap "Tap to Send Payment"\n'
            '3. Hold your phone near the receivers phone\n'
            '4. Payment will be processed automatically',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],

        SizedBox(height: 20),

        Card(
          color: Colors.grey[50],
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Status:\n\n$_status', style: TextStyle(fontSize: 14)),
          ),
        ),
        _buildAccountInfoCard(),
      ],
    ),
  );

  @override
  void dispose() {
    _amountCtrl.dispose();
    _paymentListenerTimer?.cancel();
    NfcManager.instance.stopSession();
    super.dispose();
  }
}
