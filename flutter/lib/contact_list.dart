import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:privichat_flutter/registration_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'chat_screen.dart';

class ContactList extends StatefulWidget {
  final String userId;
  final String nickname;

  ContactList({required this.userId, required this.nickname});

  @override
  _ContactListState createState() => _ContactListState();
}

class _ContactListState extends State<ContactList> {
  List<Map<String, String>> contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      List<String> storedContacts = prefs.getStringList('contacts') ?? [];
      contacts = storedContacts
          .map((contact) => Map<String, String>.from(jsonDecode(contact)))
          .toList();
    });
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
    });
  }

  Future<void> _deleteContact(int index) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      contacts.removeAt(index);
      List<String> storedContacts =
          contacts.map((contact) => jsonEncode(contact)).toList();
      prefs.setStringList('contacts', storedContacts);
    });
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
        MaterialPageRoute(builder: (context) => RegistrationScreen()),
      );
    } catch (e) {
      print('Error deleting account: $e');
    }
  }

  void _addContact() async {
    TextEditingController _controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Contact'),
          content: TextField(
            controller: _controller,
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
              child: const Text('Add'),
              onPressed: () async {
                String contactName = _controller.text.trim();

                // Check if the contact name is the same as the user's nickname
                if (contactName == widget.nickname) {
                  Navigator.of(context).pop();
                  _showErrorDialog('You cannot add yourself as a contact.');
                  return;
                }

                // Check if the contact is already in the list
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
                  String userId = result.docs.first.id;
                  Map<String, dynamic> data =
                      result.docs.first.data() as Map<String, dynamic>;
                  String? profileImage = data['profileImage'] as String?;
                  _saveContact(contactName, userId, profileImage);
                  Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact List'),
        backgroundColor: const Color(0xFF0088CC),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete_account') {
                _deleteAccount();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem<String>(
                  value: 'delete_account',
                  child: Text('Delete Account'),
                ),
              ];
            },
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
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey[200],
                    backgroundImage: contacts[index]['profileImage']!.isNotEmpty
                        ? NetworkImage(contacts[index]['profileImage']!)
                        : null,
                    radius: 25,
                    child: contacts[index]['profileImage']!.isEmpty
                        ? Icon(Icons.person, color: Colors.grey[700])
                        : null,
                  ),
                  title: Text(
                    contacts[index]['nickname']!,
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
                          otherUserId: contacts[index]['userId']!,
                          otherUserNickname: contacts[index]['nickname']!,
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
}
