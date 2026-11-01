import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/services/remote_session.dart';

void main() {
  test('pareamento QR faz roundtrip', () {
    const pairing = PairingInfo('192.168.1.12', 31234, '238491');
    final restored = PairingInfo.parse(pairing.qrData);
    expect(restored, isNotNull);
    expect(restored!.host, pairing.host);
    expect(restored.port, pairing.port);
    expect(restored.pin, pairing.pin);
  });

  test('rejeita IP inválido e PIN curto', () {
    expect(PairingInfo.validate('nao-eh-ip', 31234, '238491'), isNull);
    expect(PairingInfo.validate('192.168.1.12', 31234, '000'), isNull);
    expect(PairingInfo.validate('192.168.1.12', 99999, '238491'), isNull);
  });
}
