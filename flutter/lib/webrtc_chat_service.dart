import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCChatService {
  final String roomId;
  final String userId;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  late RTCPeerConnection _peerConnection;
  late RTCDataChannel _dataChannel;
  Function(dynamic, bool)? onMessageReceived;
  Function(bool)? onTypingIndicationReceived;

  final configuration = <String, dynamic>{
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  WebRTCChatService(
      {required this.roomId,
      required this.userId,
      this.onMessageReceived,
      this.onTypingIndicationReceived});

  Future<void> init() async {
    _peerConnection = await createPeerConnection(configuration);
    _dataChannel =
        await _peerConnection.createDataChannel("chat", RTCDataChannelInit());
    _peerConnection.onIceCandidate = _handleIceCandidate;

    _dataChannel.onDataChannelState = (state) {
      print("Data channel state: $state");
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        print("Data channel established.");
      }
    };
    _dataChannel.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        final data = message.binary;
        if (data.length == 1) {
          final isTyping = data[0] == 1;
          onTypingIndicationReceived?.call(isTyping);
        } else {
          print("Received image message");
          onMessageReceived?.call(data, true);
        }
      } else {
        print("Received text message: ${message.text}");
        onMessageReceived?.call(message.text, false);
      }
    };

    _peerConnection.onDataChannel = (RTCDataChannel dataChannel) {
      print("Data channel received: ${dataChannel.label}");
      _dataChannel = dataChannel;
    };
  }

  Future<void> sendTypingIndication(bool isTyping) async {
    if (_dataChannel.state == RTCDataChannelState.RTCDataChannelOpen) {
      final data = Uint8List(1);
      data[0] = isTyping ? 1 : 0;
      _dataChannel.send(RTCDataChannelMessage.fromBinary(data));
    }
  }

  Future<void> createOffer() async {
    final room = await firestore.collection('rooms').doc(roomId).get();
    if (room.exists) {
      await _createAnswer();
      listenForRemoteCandidates();
    } else {
      await _createRoomAndOffer();
      listenForRemoteCandidates();
    }
  }

  void sendMessage(dynamic message, {bool isImage = false}) {
    if (_dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      if (isImage) {
        print("Sending image message");
        _dataChannel!.send(RTCDataChannelMessage.fromBinary(message));
        print("Image message sent");
      } else {
        print("Sending text message: $message");
        _dataChannel!.send(RTCDataChannelMessage(message));
        print("Text message sent");
      }
    }
  }

  void _handleIceCandidate(RTCIceCandidate candidate) {
    if (candidate != null) {
      firestore.collection('rooms').doc(roomId).update({
        'candidates': FieldValue.arrayUnion([candidate.toMap()]),
      });
    }
  }

  Future<void> listenForRemoteCandidates() async {
    firestore.collection('rooms').doc(roomId).snapshots().listen((snapshot) {
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
    await firestore.collection('rooms').doc(roomId).set({
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
    });

    await for (final snapshot
        in firestore.collection('rooms').doc(roomId).snapshots()) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        if (data.containsKey('answer')) {
          print('Answer received: $data');
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
    final room = await firestore.collection('rooms').doc(roomId).get();
    final offer = RTCSessionDescription(
      room.data()!['offer']['sdp'],
      room.data()!['offer']['type'],
    );
    await _peerConnection.setRemoteDescription(offer);
    final answer = await _peerConnection.createAnswer();
    await _peerConnection.setLocalDescription(answer);
    await firestore.collection('rooms').doc(roomId).update({
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

  // Close connection
  void closeConnection() {
    _peerConnection.close();
  }

  Future<void> sendImage(Uint8List imageBytes) async {
    if (_dataChannel.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel.send(RTCDataChannelMessage.fromBinary(imageBytes));
    }
  }
}
