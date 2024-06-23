import 'dart:io';
import 'dart:typed_data';
import 'package:chewie/chewie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:mime/mime.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'webrtc_chat_service.dart';
import 'package:fluttertoast/fluttertoast.dart';

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
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isOtherUserTyping = false;
  bool _isRecording = false;
  FlutterSoundRecorder? _audioRecorder;
  FlutterSoundPlayer? _audioPlayer;
  Map<int, ChewieController> _chewieControllers = {};
  Map<int, VideoPlayerController> _videoControllers = {};

  @override
  void initState() {
    super.initState();
    _initializeConnection();
    _initializeRecorder();
    _initializePlayer();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder?.closeRecorder();
    _audioPlayer?.closePlayer();
    _chatService.sendTypingIndication(false);
    _chatService.closeConnection();
    _disposeVideoControllers();
    super.dispose();
  }

  void _disposeVideoControllers() {
    _chewieControllers.forEach((key, chewieController) {
      chewieController.dispose();
    });
    _videoControllers.forEach((key, videoController) {
      videoController.dispose();
    });
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
      onMessageReceived: (dynamic message) async {
        bool isFile = false;
        String? fileType = 'text';
        dynamic content = message;

        if (message is Uint8List) {
          isFile = true;
          fileType = lookupMimeType('', headerBytes: message);

          // Save file to temp directory
          final tempDir = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final tempFile = File(
              '${tempDir.path}/$timestamp.${fileType?.split('/')[1] ?? 'tmp'}');
          await tempFile.writeAsBytes(message);
          content = tempFile.path;
        }

        setState(() {
          _messages.add({
            'content': content,
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

  Future<void> _initializeRecorder() async {
    _audioRecorder = FlutterSoundRecorder();
    await _audioRecorder!.openRecorder();
    await _audioRecorder!.setSubscriptionDuration(Duration(milliseconds: 100));
  }

  Future<void> _initializePlayer() async {
    _audioPlayer = FlutterSoundPlayer();
    await _audioPlayer!.openPlayer();
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

  Future<void> _startRecording() async {
    await checkAndRequestPermission();

    if (await Permission.microphone.isGranted) {
      final directory = await getApplicationDocumentsDirectory();
      String filePath = '${directory.path}/audio.aac';

      // Ensure the FlutterSoundRecorder is initialized
      if (_audioRecorder == null) {
        _audioRecorder = FlutterSoundRecorder();
        await _audioRecorder!.openRecorder();
      }

      await _audioRecorder!.startRecorder(
        toFile: filePath,
        codec: Codec
            .aacADTS, // Use the AAC codec for high quality and compatibility
        bitRate: 128000, // Set a higher bitrate for better quality
        sampleRate: 48000, // Set a higher sample rate
      );

      setState(() {
        _isRecording = true;
      });
    }
  }

  Future<void> _stopRecording() async {
    final filePath = await _audioRecorder!.stopRecorder();
    setState(() {
      _isRecording = false;
    });

    if (filePath != null) {
      final File audioFile = File(filePath);
      final Uint8List fileBytes = await audioFile.readAsBytes();
      _sendAudioFile(fileBytes);
    }
  }

  Future<void> _sendAudioFile(Uint8List fileBytes) async {
    try {
      _chatService.sendFile(fileBytes);
      setState(() {
        _messages.add({
          'content': fileBytes,
          'isSent': true,
          'isFile': true,
          'fileType': 'audio/aac'
        });
      });
    } catch (e) {
      print("An error occurred while sending the audio file: $e");
    }
  }

  Future<void> _sendFile() async {
    await checkAndRequestPermission();
    final picker = ImagePicker();
    final pickedFile = await picker.pickMedia();
    if (pickedFile == null) {
      print("No file picked.");
      return;
    }

    try {
      final Uint8List fileBytes = await pickedFile.readAsBytes();
      final String? mimeType = lookupMimeType('', headerBytes: fileBytes);
      final String fileType =
          mimeType ?? 'unknown'; // Set a default type if MIME type is null

      // Save file to temp directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File(
          '${tempDir.path}/$timestamp.${mimeType?.split('/')[1] ?? 'tmp'}');
      await tempFile.writeAsBytes(fileBytes);

      print("File type: $fileType");
      _chatService.sendFile(
          fileBytes); // Ensure _chatService.sendFile can handle the data
      print("File size: ${fileBytes.length} bytes");
      setState(() {
        _messages.add({
          'content': tempFile.path, // Save the file path instead of the bytes
          'isSent': true,
          'isFile': true,
          'fileType': fileType
        });
      });
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
        return GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return Dialog(
                  child: Image.file(
                    File(messageData['content']),
                    fit: BoxFit.cover,
                  ),
                );
              },
            );
          },
          child: SizedBox(
            width: 100,
            height: 100,
            child: Image.file(
              File(messageData['content']),
              fit: BoxFit.cover,
            ),
          ),
        );
      } else if (messageData['fileType'].indexOf('audio') != -1) {
        return IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () async {
            try {
              await _audioPlayer!.startPlayer(
                fromURI: messageData['content'],
                codec: Codec.aacADTS,
              );
            } catch (e) {
              try {
                await _audioPlayer!.startPlayer(
                  fromDataBuffer: messageData['content'],
                  codec: Codec.aacADTS,
                );
              } catch (e) {
                print("An error occurred while playing the audio file: $e");
              }
            }
          },
        );
      } else if (messageData['fileType'].indexOf('mp4') != -1) {
        int index = _messages.indexOf(messageData);
        if (_videoControllers[index] == null) {
          _videoControllers[index] = VideoPlayerController.file(
            File(messageData['content']),
          );
          _chewieControllers[index] = ChewieController(
            videoPlayerController: _videoControllers[index]!,
            autoPlay: false,
            looping: false,
            allowMuting: true,
          );
        }

        return SizedBox(
          width: 200, // Set the desired width
          height: 200, // Set the desired height
          child: Chewie(controller: _chewieControllers[index]!),
        );
      } else {
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
                const SizedBox(width: 16.0),
                _isRecording
                    ? ElevatedButton(
                        onPressed: _stopRecording,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(16),
                        ),
                        child: const Icon(Icons.stop),
                      )
                    : ElevatedButton(
                        onPressed: _startRecording,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(16),
                        ),
                        child: const Icon(Icons.mic),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
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
    } else if (Platform.isIOS || Platform.isMacOS) {
      status = await Permission.photos.request();
      if (status != PermissionStatus.granted) {
        print("Permission denied.");
        return;
      }
    }

    // Request microphone permission
    status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      print("Microphone permission denied.");
      return;
    }
  }
}
