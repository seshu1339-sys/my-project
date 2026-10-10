import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/ai_agent_config.dart';

void main() {
  test('AiAgentConfig fails closed when the config doc is missing', () {
    final config = AiAgentConfig.fromMap(null);
    expect(config.enabled, false);
    expect(config.moduleEnabled('content'), false);
    expect(config.llmProvider, 'none');
    expect(config.voiceProvider, 'text-match');
  });

  test('a module is enabled only when the master switch is also on', () {
    final masterOff = AiAgentConfig.fromMap({'enabled': false, 'modules': {'content': true}});
    expect(masterOff.moduleEnabled('content'), false);

    final masterOn = AiAgentConfig.fromMap({'enabled': true, 'modules': {'content': true, 'faceId': false}});
    expect(masterOn.moduleEnabled('content'), true);
    expect(masterOn.moduleEnabled('faceId'), false);
    // Absence from the map means "on" (not yet explicitly turned off).
    expect(masterOn.moduleEnabled('somethingNeverConfigured'), true);
  });

  test('llmProvider and voiceProvider round-trip from the config doc', () {
    final config = AiAgentConfig.fromMap({'enabled': true, 'llmProvider': 'anthropic', 'voiceProvider': 'text-match'});
    expect(config.llmProvider, 'anthropic');
    expect(config.voiceProvider, 'text-match');
  });
}
