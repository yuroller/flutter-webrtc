import 'dart:async';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class LoopBackSample extends StatefulWidget {
  static String tag = 'loopback_sample';

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<LoopBackSample> {
  MediaStream _localStream;
  RTCPeerConnection _peerConnection;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  Timer _timer;

  @override
  void initState() {
    super.initState();
    initRenderers();
  }

  @override
  void deactivate() {
    super.deactivate();
    if (_inCalling) {
      _hangUp();
    }
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  void initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void handleStatsReport(Timer timer) async {
    if (_peerConnection != null) {
      var reports = await _peerConnection.getStats();
      reports.forEach((report) {
        print('report => { ');
        print('    id: ' + report.id + ',');
        print('    type: ' + report.type + ',');
        print('    timestamp: ${report.timestamp},');
        print('    values => {');
        report.values.forEach((key, value) {
          print('        ' + key + ' : ' + value.toString() + ', ');
        });
        print('    }');
        print('}');
      });
    }
  }

  void _onSignalingState(RTCSignalingState state) {
    print(state);
  }

  void _onIceGatheringState(RTCIceGatheringState state) {
    print(state);
  }

  void _onIceConnectionState(RTCIceConnectionState state) {
    print(state);
  }

  void _onPeerConnectionState(RTCPeerConnectionState state) {
    print(state);
  }

  void _onAddStream(MediaStream stream) {
    print('New stream: ' + stream.id);
    //_remoteRenderer.srcObject = stream;
  }

  void _onRemoveStream(MediaStream stream) {
    _remoteRenderer.srcObject = null;
  }

  void _onCandidate(RTCIceCandidate candidate) {
    if (candidate == null) {
      print('onCandidate: complete!');
      return;
    }
    print('onCandidate: ' + candidate.candidate);
    _peerConnection.addCandidate(candidate);
  }

  void _onTrack(RTCTrackEvent event) {
    print('onTrack');
    if (event.track.kind == 'video' && event.streams.isNotEmpty) {
      print('New stream: ' + event.streams[0].id);
      _remoteRenderer.srcObject = event.streams[0];
    }
  }

  void _onRenegotiationNeeded() {
    print('RenegotiationNeeded');
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  void _makeCall() async {
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth':
              '1280', // Provide your own width, height and frame rate here
          'minHeight': '720',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    var configuration = <String, dynamic>{
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan'
    };

    final offerSdpConstraints = <String, dynamic>{
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true,
      },
      'optional': [],
    };

    final loopbackConstraints = <String, dynamic>{
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': false},
      ],
    };

    if (_peerConnection != null) return;

    try {
      _peerConnection =
          await createPeerConnection(configuration, loopbackConstraints);

      _peerConnection.onSignalingState = _onSignalingState;
      _peerConnection.onIceGatheringState = _onIceGatheringState;
      _peerConnection.onIceConnectionState = _onIceConnectionState;
      _peerConnection.onConnectionState = _onPeerConnectionState;
      _peerConnection.onAddStream = _onAddStream;
      _peerConnection.onRemoveStream = _onRemoveStream;
      _peerConnection.onIceCandidate = _onCandidate;
      _peerConnection.onRenegotiationNeeded = _onRenegotiationNeeded;

      _peerConnection.onTrack = _onTrack;

      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;

      /* old API
      await _peerConnection.addStream(_localStream);
      // Unified-Plan
      _localStream.getTracks().forEach((track) {
        _peerConnection.addTrack(track, [_localStream]);
      });
      */
      // or

      await _peerConnection.addTransceiver(
        track: _localStream.getAudioTracks()[0],
        init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendRecv, streams: [_localStream]),
      );

      // ignore: unused_local_variable
      var transceiver = await _peerConnection.addTransceiver(
        track: _localStream.getVideoTracks()[0],
        init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendRecv, streams: [_localStream]),
      );

      /*
      // Unified-Plan Simulcast
      await _peerConnection.addTransceiver(
          track: _localStream.getVideoTracks()[0],
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly,
            streams: [_localStream],
            sendEncodings: [
              // for firefox order matters... first high resolution, then scaled resolutions...
              RTCRtpEncoding(
                rid: 'f',
                maxBitrateBps: 900000,
                numTemporalLayers: 3,
              ),
              RTCRtpEncoding(
                rid: 'h',
                numTemporalLayers: 3,
                maxBitrateBps: 300000,
                scaleResolutionDownBy: 2.0,
              ),
              RTCRtpEncoding(
                rid: 'q',
                numTemporalLayers: 3,
                maxBitrateBps: 100000,
                scaleResolutionDownBy: 4.0,
              ),
            ],
          ));

      await _peerConnection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo);
      await _peerConnection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo);
      await _peerConnection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init:
              RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
      */
      var description = await _peerConnection.createOffer(offerSdpConstraints);
      var sdp = description.sdp;
      print('sdp = $sdp');
      await _peerConnection.setLocalDescription(description);
      //change for loopback.
      description.type = 'answer';
      await _peerConnection.setRemoteDescription(description);

      /* Unfied-Plan replaceTrack
      var stream = await MediaDevices.getDisplayMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      await transceiver.sender.replaceTrack(stream.getVideoTracks()[0]);
      // do re-negotiation ....

      */
    } catch (e) {
      print(e.toString());
    }
    if (!mounted) return;

    _timer = Timer.periodic(Duration(seconds: 1), handleStatsReport);

    setState(() {
      _inCalling = true;
    });
  }

  void _hangUp() async {
    try {
      await _localStream.dispose();
      await _peerConnection.close();
      _peerConnection = null;
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    } catch (e) {
      print(e.toString());
    }
    setState(() {
      _inCalling = false;
    });
    _timer.cancel();
  }

  void _sendDtmf() async {
    var dtmfSender =
        _peerConnection.createDtmfSender(_localStream.getAudioTracks()[0]);
    await dtmfSender.insertDTMF('123#');
  }

  @override
  Widget build(BuildContext context) {
    var widgets = <Widget>[
      Expanded(
        child: RTCVideoView(_localRenderer, mirror: true),
      ),
      Expanded(
        child: RTCVideoView(_remoteRenderer),
      )
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('LoopBack example'),
        actions: _inCalling
            ? <Widget>[
                IconButton(
                  icon: Icon(Icons.keyboard),
                  onPressed: _sendDtmf,
                ),
              ]
            : null,
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Center(
            child: Container(
              decoration: BoxDecoration(color: Colors.black54),
              child: orientation == Orientation.portrait
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: widgets)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: widgets),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _inCalling ? _hangUp : _makeCall,
        tooltip: _inCalling ? 'Hangup' : 'Call',
        child: Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }
}
