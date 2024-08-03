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
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:audio_session/audio_session.dart'; // Add this import

import 'webrtc_chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String otherUserId;
  final String otherUserNickname;

  const ChatScreen(
      {super.key,
      required this.userId,
      required this.otherUserId,
      required this.otherUserNickname});

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
    _deleteTemporaryMedia();
    super.dispose();
  }

  Future<void> _deleteTemporaryMedia() async {
    final tempDir = await getTemporaryDirectory();
    final tempFiles = tempDir.listSync();
    for (var file in tempFiles) {
      if (file is File) {
        await file.delete();
      }
    }
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
    await _audioRecorder!
        .setSubscriptionDuration(const Duration(milliseconds: 10));
    if (Platform.isIOS) {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
    }
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
      print("File path: $filePath");
      // Ensure the FlutterSoundRecorder is initialized
      if (_audioRecorder == null) {
        _audioRecorder = FlutterSoundRecorder();
        await _audioRecorder!.openRecorder();
      }

      if (Platform.isIOS) {
        final session = await AudioSession.instance;
        await session.setActive(true);
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
    if (_audioRecorder == null) {
      return;
    }

    final filePath = await _audioRecorder!.stopRecorder();
    print("Recorded file path: $filePath");
    setState(() {
      _isRecording = false;
    });

    if (filePath != null) {
      final File audioFile = File(filePath);

      if (await audioFile.exists()) {
        final Uint8List fileBytes = await audioFile.readAsBytes();
        if (fileBytes.isNotEmpty) {
          _sendAudioFile(fileBytes);
        } else {
          print("Recorded file is empty.");
        }
      } else {
        print("Audio file does not exist at path: $filePath");
      }
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

  Future<void> _sendFile(XFile file) async {
    final Uint8List fileBytes = await file.readAsBytes();
    final String? mimeType = lookupMimeType('', headerBytes: fileBytes);
    final String fileType =
        mimeType ?? 'unknown'; // Set a default type if MIME type is null

    // Save file to temp directory
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile =
        File('${tempDir.path}/$timestamp.${mimeType?.split('/')[1] ?? 'tmp'}');
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
  }

  Future<void> _downloadFile(String filePath, String fileType) async {
    if (await Permission.storage.request().isGranted) {
      if (fileType.contains('image')) {
        final result = await ImageGallerySaver.saveFile(filePath,
            name: "PriviChat_${DateTime.now().millisecondsSinceEpoch}");
        if (result['isSuccess']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image saved to gallery')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save image')),
          );
        }
      } else if (fileType.contains('video')) {
        final result = await ImageGallerySaver.saveFile(filePath,
            name: "PriviChat_${DateTime.now().millisecondsSinceEpoch}");
        if (result['isSuccess']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video saved to gallery')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save video')),
          );
        }
      }
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> messageData) {
    bool isSent = messageData['isSent'];
    Alignment alignment = isSent ? Alignment.centerRight : Alignment.centerLeft;
    Color color = isSent ? const Color(0xFF0088CC) : const Color(0xFFE5E5EA);
    Color textColor = isSent ? Colors.white : Colors.black87;
    BorderRadius borderRadius = isSent
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          )
        : const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          );

    return Container(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              offset: Offset(2, 2),
              blurRadius: 4,
            ),
          ],
        ),
        child: GestureDetector(
          onLongPress: !isSent && messageData['isFile']
              ? () => _showSaveDialog(
                  messageData['content'], messageData['fileType'])
              : null,
          child: buildMessageContent(messageData, textColor),
        ),
      ),
    );
  }

  void _showSaveDialog(String filePath, String fileType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Save to Gallery'),
          content: const Text('Do you want to save this media to the gallery?'),
          actions: <Widget>[
            ElevatedButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Save to Gallery'),
              onPressed: () {
                Navigator.of(context).pop();
                _downloadFile(filePath, fileType);
              },
            ),
          ],
        );
      },
    );
  }

  Widget buildMessageContent(
      Map<String, dynamic> messageData, Color textColor) {
    print("Message data: $messageData");
    if (messageData['isFile']) {
      if (messageData['fileType'].indexOf('image') != -1) {
        return SizedBox(
          width: 150,
          height: 150,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.file(
              File(messageData['content']),
              fit: BoxFit.cover,
            ),
          ),
        );
      } else if (messageData['fileType'].indexOf('audio') != -1) {
        return IconButton(
          icon: const Icon(Icons.play_arrow, color: Colors.white),
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
          leading: const Icon(Icons.insert_drive_file, color: Colors.white),
          title:
              Text(messageData['fileType'], style: TextStyle(color: textColor)),
        );
      }
    } else {
      return SelectableText(
        messageData['content'],
        style: TextStyle(fontSize: 16, color: textColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final shouldExit = await _showExitConfirmation();
        if (shouldExit) {
          await _deleteTemporaryMedia();
        }
        return shouldExit;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Text(widget.otherUserNickname),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.call),
                onPressed: _startVoiceCall,
              ),
              IconButton(
                icon: const Icon(Icons.videocam),
                onPressed: _startVideoCall,
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0088CC),
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
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight:
                            150, // Set a maximum height for the input field
                      ),
                      child: Scrollbar(
                        child: TextField(
                          controller: _messageController,
                          onChanged: _onMessageChanged,
                          maxLines: null, // Allow unlimited lines
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
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    color: const Color(0xFF0088CC),
                    onPressed: _showAttachmentMenu,
                  ),
                  const SizedBox(width: 8.0),
                  IconButton(
                    icon: _isRecording
                        ? const Icon(Icons.stop)
                        : const Icon(Icons.mic),
                    color: const Color(0xFF0088CC),
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                  ),
                  const SizedBox(width: 8.0),
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: const Color(0xFF0088CC),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showExitConfirmation() async {
    return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Confirm Exit'),
              content: const Text(
                  'All messages will be deleted completely and will not be recoverable. Do you want to exit?'),
              actions: <Widget>[
                ElevatedButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                ElevatedButton(
                  child: const Text('Exit'),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _startVoiceCall() {
    // Implement WebRTC voice call initiation here
    print('Voice call initiated with ${widget.otherUserId}');
  }

  void _startVideoCall() {
    // Implement WebRTC video call initiation here
    print('Video call initiated with ${widget.otherUserId}');
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take Picture'),
                onTap: () {
                  _pickMedia(ImageSource.camera, mediaType: MediaType.image);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_camera_back),
                title: const Text('Take Video'),
                onTap: () {
                  _pickMedia(ImageSource.camera, mediaType: MediaType.video);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Select from Gallery'),
                onTap: () {
                  _pickMedia(ImageSource.gallery, mediaType: MediaType.image);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Select Video from Gallery'),
                onTap: () {
                  _pickMedia(ImageSource.gallery, mediaType: MediaType.video);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickMedia(ImageSource source,
      {required MediaType mediaType}) async {
    final picker = ImagePicker();
    XFile? pickedFile;
    if (mediaType == MediaType.image) {
      pickedFile = await picker.pickImage(source: source);
    } else if (mediaType == MediaType.video) {
      pickedFile = await picker.pickVideo(source: source);
    }

    if (pickedFile != null) {
      _sendFile(pickedFile);
    }
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
      print("Microphone permission denied");
      return;
    }
  }
}

enum MediaType { image, video }
