import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class FriendRequestHandler extends StatefulWidget {
  final String userId;
  final String nickname;
  final bool isDarkMode; // Add this line

  const FriendRequestHandler({
    super.key,
    required this.userId,
    required this.nickname,
    required this.isDarkMode, // Add this line
  });
  @override
  _FriendRequestHandlerState createState() => _FriendRequestHandlerState();
}

class _FriendRequestHandlerState extends State<FriendRequestHandler> {
  List<Map<String, dynamic>> friendRequests = [];
  bool _contactsUpdated = false;

  @override
  void initState() {
    super.initState();
    _loadFriendRequests();
  }

  Future<void> _loadFriendRequests() async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('friendRequests')
        .where('receiverId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'pending')
        .get();

    List<Map<String, dynamic>> requests = [];

    for (var doc in snapshot.docs) {
      Map<String, dynamic> request = {
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      };

      // Fetch sender's profile image
      DocumentSnapshot senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(request['senderId'])
          .get();

      if (senderDoc.exists) {
        Map<String, dynamic> senderData =
            senderDoc.data() as Map<String, dynamic>;
        request['senderProfileImage'] = senderData['profileImage'] ?? '';
      } else {
        request['senderProfileImage'] = '';
      }

      requests.add(request);
    }

    setState(() {
      friendRequests = requests;
    });
  }

  Future<void> _addContactToUser(String userId, String contactId,
      String contactNickname, String profileImage) async {
    // Update Firestore
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'contacts': FieldValue.arrayUnion([
        {
          'userId': contactId,
          'nickname': contactNickname,
          'profileImage': profileImage,
        }
      ]),
    });

    // Update local storage
    await _addContactLocally(contactId, contactNickname, profileImage);
  }

  Future<void> _addContactLocally(
      String userId, String nickname, String profileImage) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> storedContacts = prefs.getStringList('contacts') ?? [];

    Map<String, String> newContact = {
      'userId': userId,
      'nickname': nickname,
      'profileImage': profileImage,
    };

    storedContacts.add(jsonEncode(newContact));
    await prefs.setStringList('contacts', storedContacts);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: widget.isDarkMode ? ThemeData.dark() : ThemeData.light(),
      child: WillPopScope(
        onWillPop: () async {
          Navigator.pop(context, _contactsUpdated);
          return false;
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Friend Requests'),
            backgroundColor:
                widget.isDarkMode ? Colors.grey[900] : const Color(0xFF0088CC),
          ),
          body: friendRequests.isEmpty
              ? Center(
                  child: Text(
                    'No pending friend requests',
                    style: TextStyle(
                      color: widget.isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: friendRequests.length,
                  itemBuilder: (context, index) {
                    final request = friendRequests[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: widget.isDarkMode
                            ? Colors.grey[800]
                            : Colors.grey[200],
                        backgroundImage:
                            request['senderProfileImage'].isNotEmpty
                                ? NetworkImage(request['senderProfileImage'])
                                : null,
                        child: request['senderProfileImage'].isEmpty
                            ? Icon(
                                Icons.person,
                                color: widget.isDarkMode
                                    ? Colors.grey[300]
                                    : Colors.grey[700],
                              )
                            : null,
                      ),
                      title: Text(
                        request['senderNickname'],
                        style: TextStyle(
                          color:
                              widget.isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      subtitle: Text(
                        'Wants to add you as a friend',
                        style: TextStyle(
                          color: widget.isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () => _handleFriendRequest(
                              request['id'],
                              request['senderId'],
                              request['senderNickname'],
                              request['senderProfileImage'],
                              true,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => _handleFriendRequest(
                              request['id'],
                              request['senderId'],
                              request['senderNickname'],
                              request['senderProfileImage'],
                              false,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _handleFriendRequest(String requestId, String senderId,
      String senderNickname, String senderProfileImage, bool accept) async {
    // Update friend request status
    await FirebaseFirestore.instance
        .collection('friendRequests')
        .doc(requestId)
        .update({
      'status': accept ? 'accepted' : 'rejected',
    });

    if (accept) {
      // Add sender to receiver's contacts (local and Firestore)
      await _addContactToUser(
          widget.userId, senderId, senderNickname, senderProfileImage);

      // Show a success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Friend request accepted. $senderNickname added to your contacts.',
          ),
          backgroundColor: widget.isDarkMode ? Colors.grey[800] : null,
        ),
      );

      setState(() {
        _contactsUpdated = true;
      });
    }

    // Refresh the list
    _loadFriendRequests();
  }
}
