void main() {
  var u = Uri(scheme: 'wss', host: 'test.relay.clawke.ai', path: '/ws', queryParameters: {'token': 'abc'});
  print('No port: $u  → port=${u.port}');
  var u2 = Uri(scheme: 'wss', host: 'test.relay.clawke.ai', port: 443, path: '/ws', queryParameters: {'token': 'abc'});
  print('Port 443: $u2  → port=${u2.port}');
  var original = Uri.parse('wss://test.relay.clawke.ai/ws');
  print('Parsed hasPort=${original.hasPort} port=${original.port}');
}
