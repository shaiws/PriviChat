import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:privichat_flutter/chat_screen.dart';

class ChatsList extends StatefulWidget {
  final String userId;
  final String nickname;

  const ChatsList({super.key, required this.userId, required this.nickname});

  @override
  _ChatsListState createState() => _ChatsListState();
}

class _ChatsListState extends State<ChatsList> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  List<Map<String, String>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    setUpRealtimeListener();
  }

  void setUpRealtimeListener() {
    firestore.collection('users').snapshots().listen(
      (snapshot) {
        var users = <Map<String, String>>[];
        for (var doc in snapshot.docs) {
          var data = doc.data();
          var fetchedUserId = data['userId'];
          var nickname = data['nickname'];
          if (fetchedUserId != widget.userId) {
            users.add({'userId': fetchedUserId, 'nickname': nickname});
          }
        }
        if (mounted) {
          setState(() {
            _users = users;
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
                  child: Text('Your ID: ${widget.nickname}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text('Chat with ${_users[index]['nickname']}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                userId: widget.userId,
                                otherUserId: _users[index]['userId']!,
                                otherUserNickname: _users[index]['nickname']!,
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
