import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chats_list.dart';

class RegistrationScreen extends StatefulWidget {
  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _nicknameController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    String nickname = _nicknameController.text.trim();

    // Check if the nickname is already in use
    final QuerySnapshot result = await _firestore
        .collection('users')
        .where('nickname', isEqualTo: nickname)
        .get();

    if (result.docs.isNotEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Nickname is already in use';
      });
      return;
    }

    // Register the user anonymously and save the nickname
    try {
      UserCredential userCredential = await _auth.signInAnonymously();
      String userId = userCredential.user!.uid;

      await _firestore.collection('users').doc(userId).set({
        'userId': userId,
        'nickname': nickname,
      });

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('nickname', nickname);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (context) =>
                ChatsList(userId: userId, nickname: nickname)),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'An error occurred. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nicknameController,
              decoration:
                  const InputDecoration(labelText: 'Enter your nickname'),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _register,
                child: const Text('Register'),
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 20),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
