import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:privichat_flutter/chats_list.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  UserCredential userCredential =
      await FirebaseAuth.instance.signInAnonymously();
  String userId = userCredential.user!.uid;
  await firestore.collection('users').doc(userId).set({'userId': userId});
  runApp(MyApp(userId: userId));
}

class MyApp extends StatelessWidget {
  final String userId;

  const MyApp({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PriviChat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ChatsList(userId: userId),
    );
  }
}
