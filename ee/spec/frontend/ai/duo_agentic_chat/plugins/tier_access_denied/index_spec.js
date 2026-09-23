import { tierAccessDeniedPlugin } from 'ee/ai/duo_agentic_chat/plugins/tier_access_denied';
import MessageTierAccessDenied from 'ee/ai/duo_agentic_chat/plugins/tier_access_denied/components/message_tier_access_denied.vue';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';

describe('tierAccessDeniedPlugin', () => {
  const [{ matchMessage, defaultProps }] = tierAccessDeniedPlugin.messageWidgets;

  // Guards the shipped plugin against its own contract: the registry drops anything
  // malformed, so a broken descriptor would otherwise only show up as a missing widget.
  it('satisfies the plugin contract', () => {
    const registry = new DuoChatPluginRegistry();

    registry.registerPlugin(tierAccessDeniedPlugin);

    expect(registry.plugins).toEqual([tierAccessDeniedPlugin]);
  });

  it('is named after its plugin directory', () => {
    expect(tierAccessDeniedPlugin.name).toBe('tier_access_denied');
  });

  it('renders tier_access_denied messages with MessageTierAccessDenied', () => {
    expect(tierAccessDeniedPlugin.messageWidgets).toEqual([
      {
        matchMessage: expect.any(Function),
        component: MessageTierAccessDenied,
        defaultProps: expect.any(Function),
      },
    ]);
  });

  describe('matchMessage', () => {
    it('returns true when message_sub_type is tier_access_denied', () => {
      expect(matchMessage({ message_sub_type: 'tier_access_denied' })).toBe(true);
    });

    it('returns false when message_sub_type is a different value', () => {
      expect(matchMessage({ message_sub_type: 'start_flow' })).toBe(false);
    });

    it('returns false when message_sub_type is undefined', () => {
      expect(matchMessage({ message_sub_type: undefined })).toBe(false);
    });
  });

  describe('defaultProps', () => {
    const message = { message_sub_type: 'tier_access_denied' };

    it('forwards the message and takes the whole widget config off duoChatState', () => {
      const duoChatState = {
        canBuyAddon: true,
        tierUpgradePath: '/-/subscriptions/new?namespace_id=42',
        isHandRaiseLeadAvailable: true,
      };

      expect(defaultProps(message, '/work/dir', { duoChatState })).toEqual({
        message,
        ...duoChatState,
      });
    });

    // A widget mounted without a state manager above it resolves against nothing, which
    // must fall back to the read-only rendering rather than throw.
    it.each([{}, { duoChatState: {} }])('falls back to hiding both CTAs for %p', (dependencies) => {
      expect(defaultProps(message, '/work/dir', dependencies)).toEqual({
        message,
        canBuyAddon: false,
        tierUpgradePath: '',
        isHandRaiseLeadAvailable: false,
      });
    });
  });
});
