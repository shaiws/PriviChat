import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:privichat_flutter/chat_screen.dart';

class ChatsList extends StatefulWidget {
  final String userId;

  const ChatsList({super.key, required this.userId});

  @override
  _ChatsListState createState() => _ChatsListState();
}

class _ChatsListState extends State<ChatsList> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  List<String> _userIds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    setUpRealtimeListener();
  }

  void setUpRealtimeListener() {
    firestore.collection('users').snapshots().listen(
      (snapshot) {
        var userIds = <String>[];
        for (var doc in snapshot.docs) {
          var data = doc.data();
          var fetchedUserId = data['userId'];
          if (fetchedUserId != widget.userId) {
            userIds.add(fetchedUserId);
          }
        }
        if (mounted) {
          setState(() {
            _userIds = userIds;
            _isLoading = false;
          });
        }
      },
      onError: (error) => print("Error listening to user updates: $error"),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat List'),
        actions: const [
          // Optionally add a logout icon or settings icon here
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Icon(Icons.account_circle),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Your ID: ${widget.userId}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _userIds.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text('Chat with ${_userIds[index]}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                userId: widget.userId,
                                otherUserId: _userIds[index],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                )
              ],
            ),
    );
  }
}
