import 'package:flutter/material.dart';

class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Terms & Conditions'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Text(
                'Terms and Conditions',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),

              Text(
                'By using this application, you agree to the following terms and conditions regarding data access, API usage, and responsibilities:',
              ),
              SizedBox(height: 24),

              Text(
                '📡 APIs and External Services Used',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),

              Text(
                '1. Firebase Authentication APIs:'
                '  - Used to manage user login, registration, and secure session handling.'
                '  - Provided by Google Firebase.',
              ),
              SizedBox(height: 12),

              Text(
                '2. Firebase Firestore Database APIs:'
                '  - Used to read/write data such as user profiles, transactions, and payment notifications.'
                '  - Access is secured through Firebase Auth and Firestore security rules.',
              ),
              SizedBox(height: 12),

              Text(
                '3. JOFS (Jordan Open Finance Services) APIs:'
                '  - These APIs are used for open banking operations via secure REST endpoints.'
                '    - POST /login: Authenticate to JOFS'
                '    - POST /register: Register a user in JOFS system'
                '    - GET /accounts: Retrieve user’s authorized bank accounts'
                '    - GET /accounts/{accountId}/balances: Retrieve account balance'
                '    - POST /proxy/resolve: Resolve recipient alias (e.g. CLIQ)'
                '    - POST /PIS/initiation: Initiate a payment (e.g. NFC P2P)'
                '  - Requires Bearer Token and JWS Signature',
              ),
              SizedBox(height: 12),

              Text(
                '4. Google Gemini AI (Generative AI API):'
                '  - Used to generate smart suggestions or financial insights inside the app.'
                '  - All prompts and results are processed securely through Googles Gemini API.',
              ),
              SizedBox(height: 24),

              Text(
                '🔐 Data Privacy and Security',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Your personal data, account information, and payment details are handled securely. '
                'Authentication is enforced using Firebase Auth. All financial data exchange with JOFS is encrypted '
                'and requires proper authorization headers. We do not share your data with third parties without your consent.',
              ),
              SizedBox(height: 24),

              Text(
                '📄 Acceptance of Terms',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'By using this app, you acknowledge and agree to these Terms and Conditions. '
                'Continued use of the app following changes to these terms will be regarded as acceptance of the updated terms.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
