import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:privichat_flutter/registration_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'chat_screen.dart';
import 'friend_request_handler.dart';

class ContactList extends StatefulWidget {
  final String userId;
  final String nickname;

  const ContactList({super.key, required this.userId, required this.nickname});

  @override
  _ContactListState createState() => _ContactListState();
}

class _ContactListState extends State<ContactList> {
  List<Map<String, String>> contacts = [];
  List<Map<String, String>> filteredContacts = [];
  bool isSearching = false;
  TextEditingController searchController = TextEditingController();
  bool isLoading = true;

  int pendingFriendRequests = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadContacts();
    await _checkPendingFriendRequests();
    _listenForFriendRequests();
    setState(() {
      isLoading = false;
    });
  }

  @override
  void dispose() {
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    filterContacts();
  }

  Future<void> _syncContactsWithFirestore() async {
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();

    if (userDoc.exists) {
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      List<dynamic> firestoreContacts = userData['contacts'] ?? [];

      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> storedContacts = prefs.getStringList('contacts') ?? [];

      List<Map<String, String>> updatedContacts = firestoreContacts
          .map((contact) {
            return {
              'userId': contact['userId'],
              'nickname': contact['nickname'],
              'profileImage': contact['profileImage'] ?? '',
            };
          })
          .toList()
          .cast<Map<String, String>>();

      storedContacts =
          updatedContacts.map((contact) => jsonEncode(contact)).toList();
      await prefs.setStringList('contacts', storedContacts);

      setState(() {
        contacts = updatedContacts;
        filteredContacts = contacts;
      });
    }
  }

  Future<void> _loadContacts() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      List<String> storedContacts = prefs.getStringList('contacts') ?? [];
      contacts = storedContacts
          .map((contact) => Map<String, String>.from(jsonDecode(contact)))
          .toList();
      filteredContacts = contacts;
    });
  }

  Future<void> _checkPendingFriendRequests() async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('friendRequests')
        .where('receiverId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'pending')
        .get();

    setState(() {
      pendingFriendRequests = snapshot.docs.length;
    });

    if (pendingFriendRequests > 0) {
      _showFriendRequestNotification();
    }
  }

  void _showFriendRequestNotification() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('You have $pendingFriendRequests new friend request(s)!'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            _showFriendRequests();
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _saveContact(
      String nickname, String userId, String? profileImage) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      contacts.add({
        'nickname': nickname,
        'userId': userId,
        'profileImage': profileImage ?? '',
      });
      List<String> storedContacts =
          contacts.map((contact) => jsonEncode(contact)).toList();
      prefs.setStringList('contacts', storedContacts);
      filteredContacts = contacts;
    });
  }

  Future<void> _deleteContact(int index) async {
    bool confirmDelete = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this contact?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      setState(() {
        String deletedUserId = filteredContacts[index]['userId']!;
        contacts.removeWhere((contact) => contact['userId'] == deletedUserId);
        filteredContacts.removeAt(index);
        List<String> storedContacts =
            contacts.map((contact) => jsonEncode(contact)).toList();
        prefs.setStringList('contacts', storedContacts);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact removed from your list')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .delete();

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const RegistrationScreen()),
      );
    } catch (e) {
      print('Error deleting account: $e');
    }
  }

  void _addContact() async {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Contact'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Enter contact name"),
          ),
          actions: <Widget>[
            ElevatedButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Send Friend Request'),
              onPressed: () async {
                String contactName = controller.text.trim();

                if (contactName == widget.nickname) {
                  Navigator.of(context).pop();
                  _showErrorDialog('You cannot add yourself as a contact.');
                  return;
                }

                bool isDuplicate = contacts
                    .any((contact) => contact['nickname'] == contactName);
                if (isDuplicate) {
                  Navigator.of(context).pop();
                  _showErrorDialog('This contact is already in your list.');
                  return;
                }

                QuerySnapshot result = await FirebaseFirestore.instance
                    .collection('users')
                    .where('nickname', isEqualTo: contactName)
                    .get();

                if (result.docs.isNotEmpty) {
                  String contactUserId = result.docs.first.id;
                  await _sendFriendRequest(contactUserId, contactName);
                  await _addContactToSenderList(contactUserId, contactName);
                  Navigator.of(context).pop();
                  _showSuccessDialog(
                      'Friend request sent and contact added to your list!');
                } else {
                  Navigator.of(context).pop();
                  _showErrorDialog(
                      'The contact you are looking for was not found.');
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendFriendRequest(
      String contactUserId, String contactName) async {
    await FirebaseFirestore.instance.collection('friendRequests').add({
      'senderId': widget.userId,
      'senderNickname': widget.nickname,
      'receiverId': contactUserId,
      'receiverNickname': contactName,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _addContactToSenderList(
      String contactUserId, String contactName) async {
    // Fetch the contact's profile image
    DocumentSnapshot contactDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(contactUserId)
        .get();

    String profileImage = '';
    if (contactDoc.exists) {
      Map<String, dynamic> contactData =
          contactDoc.data() as Map<String, dynamic>;
      profileImage = contactData['profileImage'] ?? '';
    }

    // Add to Firestore
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({
      'contacts': FieldValue.arrayUnion([
        {
          'userId': contactUserId,
          'nickname': contactName,
          'profileImage': profileImage,
        }
      ]),
    });

    // Add to local storage
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> storedContacts = prefs.getStringList('contacts') ?? [];

    Map<String, String> newContact = {
      'userId': contactUserId,
      'nickname': contactName,
      'profileImage': profileImage,
    };

    storedContacts.add(jsonEncode(newContact));
    await prefs.setStringList('contacts', storedContacts);

    // Update the state
    setState(() {
      contacts.add(newContact);
      filteredContacts = List.from(contacts);
    });
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Success'),
          content: Text(message),
          actions: <Widget>[
            ElevatedButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: <Widget>[
            ElevatedButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void filterContacts() {
    List<Map<String, String>> contacts = [];
    contacts.addAll(contacts);
    if (searchController.text.isNotEmpty) {
      contacts.retainWhere((contact) {
        String searchTerm = searchController.text.toLowerCase();
        String contactName = contact['nickname']!.toLowerCase();
        return contactName.contains(searchTerm);
      });
    }
    setState(() {
      filteredContacts = contacts;
    });
  }

  void _listenForFriendRequests() {
    FirebaseFirestore.instance
        .collection('friendRequests')
        .where('receiverId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      setState(() {
        pendingFriendRequests = snapshot.docs.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: isSearching
            ? TextField(
                controller: searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search contacts...',
                  border: InputBorder.none,
                ),
                style: const TextStyle(color: Colors.white, fontSize: 16.0),
              )
            : const Text('Contact List'),
        backgroundColor: const Color(0xFF0088CC),
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) {
                  searchController.clear();
                  filteredContacts = contacts;
                }
              });
            },
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete_account') {
                    _deleteAccount();
                  } else if (value == 'friend_requests') {
                    _showFriendRequests();
                  }
                },
                itemBuilder: (BuildContext context) {
                  return [
                    const PopupMenuItem<String>(
                      value: 'friend_requests',
                      child: Text('Friend Requests'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete_account',
                      child: Text('Delete Account'),
                    ),
                  ];
                },
              ),
              if (pendingFriendRequests > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$pendingFriendRequests',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hello, ${widget.nickname}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                FloatingActionButton(
                  onPressed: _addContact,
                  backgroundColor: const Color(0xFF0088CC),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredContacts.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey[200],
                    backgroundImage: filteredContacts[index]['profileImage']!
                            .isNotEmpty
                        ? NetworkImage(filteredContacts[index]['profileImage']!)
                        : null,
                    radius: 25,
                    child: filteredContacts[index]['profileImage']!.isEmpty
                        ? Icon(Icons.person, color: Colors.grey[700])
                        : null,
                  ),
                  title: Text(
                    filteredContacts[index]['nickname']!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      _deleteContact(index);
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          userId: widget.userId,
                          otherUserId: filteredContacts[index]['userId']!,
                          otherUserNickname: filteredContacts[index]
                              ['nickname']!,
                          otherUserProfileImage: filteredContacts[index]
                              ['profileImage'],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFriendRequests() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FriendRequestHandler(
          userId: widget.userId,
          nickname: widget.nickname,
        ),
      ),
    );

    if (result == true) {
      // Refresh contacts if changes were made
      _loadContacts();
    }
  }
}
