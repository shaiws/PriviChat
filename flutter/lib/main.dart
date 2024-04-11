import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Chat App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: SafeArea(child: ChatScreen()),
    );
  }
}
