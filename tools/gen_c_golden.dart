import 'dart:convert';
import 'package:myhome/protocol/ble_frame.dart';
import 'package:myhome/protocol/fragment.dart';
import 'package:myhome/protocol/frame_sequencer.dart';

void main() {
  final seq = FrameSequencer();
  void emit(String name, int frameType, int msgId, String json) {
    final f = Fragmenter(mtu: 247, frameType: frameType, sequencer: seq);
    for (final fr in f.fragment(msgId, utf8.encode(json))) {
      final b = fr.encode();
      // ignore: avoid_print
      print('$name ${b.length}B: '
          '${List.generate(b.length, (i) => '0x${b[i].toRadixString(16).padLeft(2, '0')}').join(', ')}');
    }
  }
  emit('HELLO', FrameType.hello, 1, '{"request_id":1,"protocol_version":1}');
  emit('PING', FrameType.ping, 2, '{"request_id":2}');
  emit('STATEREQ', FrameType.stateRequest, 3, '{"request_id":3}');
  emit('CMD', FrameType.command, 4,
      '{"request_id":10,"cmd":"light.set_brightness","params":{"value":50}}');
}
