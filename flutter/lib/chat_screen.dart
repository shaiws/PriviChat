import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'webrtc_chat_service.dart';
import 'package:mime/mime.dart';
import 'package:image_picker/image_picker.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String otherUserId;

  const ChatScreen(
      {super.key, required this.userId, required this.otherUserId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  late WebRTCChatService _chatService;
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isOtherUserTyping = false;

  @override
  void initState() {
    super.initState();
    _initializeConnection();
  }

  @override
  void dispose() {
    _roomIdController.dispose();
    _userIdController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _chatService.sendTypingIndication(false);
    _chatService.closeConnection();
    super.dispose();
  }

  void _initializeConnection() async {
    String localId = widget.userId;
    String remoteId = widget.userId;
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    DocumentSnapshot room =
        await firestore.collection('rooms').doc(localId).get();

    if (!room.exists) {
      room = await firestore.collection('rooms').doc(widget.otherUserId).get();
      if (room.exists) {
        remoteId = widget.otherUserId;
        localId = widget.userId;
      }
    }

    _chatService = WebRTCChatService(
      remoteId: remoteId,
      localId: localId,
      onMessageReceived: (dynamic message) {
        bool isFile = false;
        String? fileType = 'text';

        if (message is Uint8List) {
          isFile = true;
          fileType = lookupMimeType('', headerBytes: message);
        }

        setState(() {
          _messages.add({
            'content': message,
            'isSent': false,
            'isFile': isFile,
            'fileType': fileType
          });
        });
        _scrollToBottom();
      },
      onTypingIndicationReceived: (isTyping) {
        setState(() {
          _isOtherUserTyping = isTyping;
        });
      },
    );

    _chatService.init().then((_) {
      _chatService.createOffer();
    });
  }

  void _sendMessage() {
    final message = _messageController.text;
    if (message.isNotEmpty) {
      _chatService.sendMessage(message);
      setState(() {
        _messages.add({'content': message, 'isSent': true, 'isFile': false});
      });
      _scrollToBottom();

      _messageController.clear();
    }
    _chatService.sendTypingIndication(false);
  }

  void _scrollToBottom() {
    // Schedule a task to scroll to the bottom of the list after the UI build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    });
  }

  void _onMessageChanged(String text) {
    _chatService.sendTypingIndication(text.isNotEmpty);
  }

  Future<void> checkAndRequestPermission() async {
    var status;
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt <= 32) {
        status = await Permission.storage.request();
      } else {
        status = await Permission.photos.request();
      }

      if (status != PermissionStatus.granted) {
        print("Permission denied.");
        return;
      }
    } else if (Platform.isIOS) {
      status = await Permission.photos.request();
      if (status != PermissionStatus.granted) {
        print("Permission denied.");
        return;
      }
    }
  }

  Future<void> _sendFile() async {
    checkAndRequestPermission();
    final picker = ImagePicker();
    final pickedFile = await picker.pickMedia();
    if (pickedFile == null) {
      print("No file picked.");
      return;
    }

    try {
      final Uint8List fileBytes = await pickedFile.readAsBytes();

      final String? mimeType = lookupMimeType(pickedFile.path);
      final String fileType =
          mimeType ?? 'unknown'; // Set a default type if MIME type is null

      print("File size: ${fileBytes.length} bytes");
      setState(() {
        _messages.add({
          'content': fileBytes,
          'isSent': true,
          'isFile': true,
          'fileType': fileType
        });
      });
      _chatService.sendFile(
          fileBytes); // Ensure _chatService.sendFile can handle the data
    } catch (e) {
      print("An error occurred while processing the file: $e");
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> messageData) {
    bool isSent = messageData['isSent'];
    Alignment alignment = isSent ? Alignment.centerRight : Alignment.centerLeft;
    Color color =
        isSent ? Colors.blue[200]! : const Color.fromARGB(255, 111, 175, 92);
    BorderRadius borderRadius = isSent
        ? const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          )
        : const BorderRadius.only(
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          );

    return Container(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
        ),
        child: buildMessage(messageData),
      ),
    );
  }

  Widget buildMessage(messageData) {
    if (messageData['isFile']) {
      if (messageData['fileType'].indexOf('image') != -1) {
        // Handle image files
        return GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return Dialog(
                  child: Image.memory(messageData['content']),
                );
              },
            );
          },
          child: SizedBox(
            width: 100, // specify your desired width
            height: 100, // specify your desired height
            child: Image.memory(
              messageData['content'],
              fit: BoxFit.cover,
            ),
          ),
        );
      } else if (messageData['fileType'] == 'mp4') {
        // Handle video files
        VideoPlayerController controller =
            VideoPlayerController.network(messageData['content']);
        return VideoPlayer(controller);
      } else {
        // Handle other types of files
        return ListTile(
          leading: const Icon(Icons.insert_drive_file),
          title: Text(messageData['fileType']),
        );
      }
    } else {
      return SelectableText(
        messageData['content'],
        style: const TextStyle(fontSize: 16),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PriviChat with user ID: ${widget.otherUserId}'),
      ),
      body: Column(
        children: [
          if (_isOtherUserTyping)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Typing...',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onChanged: _onMessageChanged,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16.0),
                ElevatedButton(
                  onPressed: _sendMessage,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Icon(Icons.send),
                ),
                const SizedBox(width: 16.0),
                ElevatedButton(
                  onPressed: _sendFile,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Icon(Icons.attach_file),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
