import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:fluttertoast/fluttertoast.dart';

class WebRTCChatService {
  final String remoteId;
  final String localId;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  late RTCPeerConnection _peerConnection;
  late RTCDataChannel _dataChannel;
  Function(dynamic)? onMessageReceived;
  Function(bool)? onTypingIndicationReceived;
  Uint8List _receivedFileBuffer = Uint8List(0);

  final configuration = <String, dynamic>{
    'iceServers': [
      {
        "urls": [
          "stun:stun1.l.google.com:19302",
          "stun:stun2.l.google.com:19302",
          "stun:stun3.l.google.com:19302",
          "stun:stun4.l.google.com:19302",
          "stun:stun.relay.metered.ca:80"
        ]
      },
      {
        "urls": "turn:global.relay.metered.ca:80",
        "username": "d76b7ca8eacf8cf31d34d49e",
        "credential": "4lNmW4YPP2j8nmeg",
      },
      {
        "urls": "turn:global.relay.metered.ca:80?transport=tcp",
        "username": "d76b7ca8eacf8cf31d34d49e",
        "credential": "4lNmW4YPP2j8nmeg",
      },
      {
        "urls": "turn:global.relay.metered.ca:443",
        "username": "d76b7ca8eacf8cf31d34d49e",
        "credential": "4lNmW4YPP2j8nmeg",
      },
      {
        "urls": "turns:global.relay.metered.ca:443?transport=tcp",
        "username": "d76b7ca8eacf8cf31d34d49e",
        "credential": "4lNmW4YPP2j8nmeg",
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  WebRTCChatService({
    required this.remoteId,
    required this.localId,
    this.onMessageReceived,
    this.onTypingIndicationReceived,
  });

  Future<void> init() async {
    _peerConnection = await createPeerConnection(configuration);
    _dataChannel =
        await _peerConnection.createDataChannel("chat", RTCDataChannelInit());
    _peerConnection.onIceCandidate = _handleIceCandidate;

    _dataChannel.onDataChannelState = _handleDataChannelState;
    _dataChannel.onMessage = _handleDataChannelMessage;

    _peerConnection.onDataChannel = (RTCDataChannel dataChannel) {
      _dataChannel = dataChannel;
    };
  }

  void _handleDataChannelState(RTCDataChannelState state) {
    if (state == RTCDataChannelState.RTCDataChannelOpen) {
      _showToast("P2P connection established!", Colors.green);
    }
  }

  void _handleDataChannelMessage(RTCDataChannelMessage message) {
    if (message.isBinary) {
      Uint8List receivedBytes = message.binary;

      // Check for EOF and Typing Indication (uncompressed single byte)
      if (receivedBytes.length == 1) {
        if (receivedBytes[0] == 2) {
          // EOF Marker
          try {
            Uint8List decompressedBytes = decompressFile(_receivedFileBuffer);
            onMessageReceived?.call(decompressedBytes);
          } catch (e) {
            print("Error decompressing file: $e");
          }
          _receivedFileBuffer = Uint8List(0); // Reset buffer
        } else if (receivedBytes[0] == 1 || receivedBytes[0] == 0) {
          // Typing Indication
          onTypingIndicationReceived?.call(receivedBytes[0] == 1);
        }
      } else {
        // Append to buffer if it's part of a file
        _receivedFileBuffer =
            Uint8List.fromList(_receivedFileBuffer + receivedBytes);
      }
    } else {
      onMessageReceived?.call(message.text);
    }
  }

  Future<void> sendFile(Uint8List fileBytes) async {
    if (_dataChannel.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        Uint8List compressedFile = compressFile(fileBytes);
        int chunkSize = 16 * 1024; // 16 KB chunks
        for (int i = 0; i < compressedFile.length; i += chunkSize) {
          int end = (i + chunkSize < compressedFile.length)
              ? i + chunkSize
              : compressedFile.length;
          Uint8List chunk = compressedFile.sublist(i, end);
          _dataChannel.send(RTCDataChannelMessage.fromBinary(chunk));
        }
        // Send EOF marker
        await sendEOFIndicator();
      } catch (e) {
        print("Error sending file: $e");
        _showToast("Error sending file", Colors.red);
      }
    } else {
      _showToast("Data channel is not open", Colors.red);
    }
  }

  Uint8List compressFile(Uint8List fileBytes) {
    final archive = Archive();
    final archiveFile = ArchiveFile('file', fileBytes.length, fileBytes);
    archive.addFile(archiveFile);
    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes!);
  }

  Uint8List decompressFile(Uint8List compressedFileBytes) {
    final archive = ZipDecoder().decodeBytes(compressedFileBytes);
    final fileBytes = archive.first.content as Uint8List;
    return fileBytes;
  }

  Future<void> sendTypingIndication(bool isTyping) async {
    if (_dataChannel.state == RTCDataChannelState.RTCDataChannelOpen) {
      final data = Uint8List(1)..[0] = isTyping ? 1 : 0;
      _dataChannel.send(RTCDataChannelMessage.fromBinary(data));
    }
  }

  Future<void> sendEOFIndicator() async {
    if (_dataChannel.state == RTCDataChannelState.RTCDataChannelOpen) {
      final data = Uint8List(1)..[0] = 2;
      _dataChannel.send(RTCDataChannelMessage.fromBinary(data));
    }
  }

  Future<void> createOffer() async {
    final room = await firestore.collection('rooms').doc(remoteId).get();
    if (room.exists) {
      await _createAnswer();
      listenForRemoteCandidates();
    } else {
      await _createRoomAndOffer();
      listenForRemoteCandidates();
    }
  }

  void sendMessage(dynamic message) {
    if (_dataChannel.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel.send(RTCDataChannelMessage(message));
    }
  }

  void _handleIceCandidate(RTCIceCandidate candidate) {
    firestore.collection('rooms').doc(remoteId).update({
      'candidates': FieldValue.arrayUnion([candidate.toMap()]),
    });
  }

  Future<void> listenForRemoteCandidates() async {
    firestore.collection('rooms').doc(remoteId).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        if (data.containsKey('candidates')) {
          for (final candidateMap in data['candidates']) {
            _peerConnection.addCandidate(RTCIceCandidate(
              candidateMap['candidate'],
              candidateMap['sdpMid'],
              candidateMap['sdpMLineIndex'],
            ));
          }
        }
      }
    });
  }

  Future<void> _createRoomAndOffer() async {
    final offer = await _createOffer();
    await firestore.collection('rooms').doc(remoteId).set({
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
    });

    await for (final snapshot
        in firestore.collection('rooms').doc(remoteId).snapshots()) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        if (data.containsKey('answer')) {
          await _setRemoteDescription(data['answer']);
          break;
        }
      }
    }
  }

  Future<RTCSessionDescription> _createOffer() async {
    final offer = await _peerConnection.createOffer();
    await _peerConnection.setLocalDescription(offer);
    return offer;
  }

  Future<void> _createAnswer() async {
    final room = await firestore.collection('rooms').doc(remoteId).get();
    final offer = RTCSessionDescription(
      room.data()!['offer']['sdp'],
      room.data()!['offer']['type'],
    );
    await _peerConnection.setRemoteDescription(offer);
    final answer = await _peerConnection.createAnswer();
    await _peerConnection.setLocalDescription(answer);
    await firestore.collection('rooms').doc(remoteId).update({
      'answer': {
        'sdp': answer.sdp,
        'type': answer.type,
      },
    });
  }

  Future<void> _setRemoteDescription(Map<String, dynamic> answerMap) async {
    final rtcSessionDescription = RTCSessionDescription(
      answerMap['sdp'],
      answerMap['type'],
    );
    await _peerConnection.setRemoteDescription(rtcSessionDescription);
  }

  void closeConnection() {
    print("Closing connection");
    firestore.collection('rooms').doc(remoteId).delete();
    _peerConnection.close();
    _dataChannel.close();
  }

  void _showToast(String message, Color backgroundColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: backgroundColor,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }
}
