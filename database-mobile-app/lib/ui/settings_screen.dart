import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _queryTimeoutController = TextEditingController();
  final _transactionTimeoutController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final queryTimeout = prefs.getInt('query_timeout_seconds') ?? 5;
    final transactionTimeout = prefs.getInt('transaction_timeout_seconds') ?? 5;
    
    _queryTimeoutController.text = queryTimeout.toString();
    _transactionTimeoutController.text = transactionTimeout.toString();
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final queryTimeout = int.tryParse(_queryTimeoutController.text) ?? 5;
    final transactionTimeout = int.tryParse(_transactionTimeoutController.text) ?? 5;
    
    await prefs.setInt('query_timeout_seconds', queryTimeout);
    await prefs.setInt('transaction_timeout_seconds', transactionTimeout);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Database Configuration', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _queryTimeoutController,
                      decoration: const InputDecoration(
                        labelText: 'Standard Query Timeout (seconds)',
                        helperText: 'For single reads and writes. Default is 5.',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _transactionTimeoutController,
                      decoration: const InputDecoration(
                        labelText: 'Transaction Timeout (seconds)',
                        helperText: 'For batch transactions. Default is 5.',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Settings'),
                    )
                  ],
                ),
              ),
            ),
          ),
    );
  }
}
