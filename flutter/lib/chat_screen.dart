import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'webrtc_chat_service.dart';
import 'package:permission_handler/permission_handler.dart';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late WebRTCChatService _chatService;
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isOtherUserTyping = false;

  @override
  void dispose() {
    _roomIdController.dispose();
    _userIdController.dispose();
    _messageController.dispose();
    _chatService.closeConnection();
    super.dispose();
  }

  void _initializeConnection() {
    final roomId = _roomIdController.text;
    final userId = _userIdController.text;

    _chatService = WebRTCChatService(
      roomId: roomId,
      userId: userId,
      onMessageReceived: (message, isImage) {
        setState(() {
          if (isImage) {
            _messages
                .add({'imageBytes': message, 'isSent': false, 'isImage': true});
          } else {
            _messages.add({'text': message, 'isSent': false, 'isImage': false});
          }
        });
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
        _messages.add({'text': message, 'isSent': true, 'isImage': false});
      });
      _messageController.clear();
    }
    _chatService.sendTypingIndication(false);
  }

  void _sendImage() async {
    final status = await Permission.storage.request();
    if (status == PermissionStatus.granted) {
      final picker = ImagePicker();
      final pickedImage = await picker.pickImage(source: ImageSource.gallery);
      if (pickedImage != null) {
        final imageBytes = await pickedImage.readAsBytes();
        _chatService.sendMessage(imageBytes, isImage: true);
        setState(() {
          _messages
              .add({'imageBytes': imageBytes, 'isSent': true, 'isImage': true});
        });
      }
    } else {
      // Permission denied, handle accordingly
      print('Storage permission denied');
    }
  }

  void _onMessageChanged(String text) {
    _chatService.sendTypingIndication(text.isNotEmpty);
  }

  Widget _buildMessageBubble(Map<String, dynamic> messageData) {
    print(messageData);
    bool isSent = messageData['isSent'];
    bool isImage = messageData['isImage'];
    Alignment alignment = isSent ? Alignment.centerRight : Alignment.centerLeft;
    Color color =
        isSent ? Colors.blue[200]! : Color.fromARGB(255, 111, 175, 92)!;
    BorderRadius borderRadius = isSent
        ? BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          )
        : BorderRadius.only(
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
        child: isImage
            ? Image.memory(messageData['imageBytes'])
            : SelectableText(
                messageData['text'],
                style: TextStyle(fontSize: 16),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebRTC Chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomIdController,
                    decoration: InputDecoration(
                      labelText: 'Room ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 16.0),
                Expanded(
                  child: TextField(
                    controller: _userIdController,
                    decoration: InputDecoration(
                      labelText: 'User ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 16.0),
                ElevatedButton(
                  onPressed: _initializeConnection,
                  child: Text('Connect'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isOtherUserTyping)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Typing...',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),
          Divider(height: 1),
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
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                // SizedBox(width: 16.0),
                // ElevatedButton(
                //   onPressed: _sendImage,
                //   child: Icon(Icons.image),
                //   style: ElevatedButton.styleFrom(
                //     shape: CircleBorder(),
                //     padding: EdgeInsets.all(16),
                //   ),
                // ),
                SizedBox(width: 16.0),
                ElevatedButton(
                  onPressed: _sendMessage,
                  child: Icon(Icons.send),
                  style: ElevatedButton.styleFrom(
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
