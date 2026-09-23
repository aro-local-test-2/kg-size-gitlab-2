import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import BypassSettings from 'ee/security_orchestration/components/policy_editor/dependency_firewall/advanced_settings/bypass_settings.vue';
import UsersSelector from 'ee/security_orchestration/components/policy_editor/scan_result/advanced_settings/policy_exceptions/users_selector.vue';
import TokensSelector from 'ee/security_orchestration/components/policy_editor/scan_result/advanced_settings/policy_exceptions/tokens_selector.vue';

describe('BypassSettings', () => {
  let wrapper;

  const createWrapper = (bypassSettings = {}) => {
    wrapper = shallowMountExtended(BypassSettings, {
      propsData: { bypassSettings },
      provide: { availableAccessTokens: [] },
    });
  };

  const findUsersSelector = () => wrapper.findComponent(UsersSelector);
  const findTokensSelector = () => wrapper.findComponent(TokensSelector);

  it('passes the current users and tokens through to their selectors', () => {
    createWrapper({ users: [{ id: 1 }], access_tokens: [{ id: 2 }] });
    expect(findUsersSelector().props('selectedUsers')).toEqual([{ id: 1 }]);
    expect(findTokensSelector().props('selectedTokens')).toEqual([{ id: 2 }]);
  });

  it('defaults to empty selections when bypassSettings is empty', () => {
    createWrapper();
    expect(findUsersSelector().props('selectedUsers')).toEqual([]);
    expect(findTokensSelector().props('selectedTokens')).toEqual([]);
  });

  it('emits changed with users added, preserving existing tokens', () => {
    createWrapper({ access_tokens: [{ id: 2 }] });
    findUsersSelector().vm.$emit('set-users', [{ id: 1 }]);
    expect(wrapper.emitted('changed')[0]).toEqual([
      'bypass_settings',
      { users: [{ id: 1 }], access_tokens: [{ id: 2 }] },
    ]);
  });

  it('emits changed with tokens added, preserving existing users', () => {
    createWrapper({ users: [{ id: 1 }] });
    findTokensSelector().vm.$emit('set-access-tokens', [{ id: 2 }]);
    expect(wrapper.emitted('changed')[0]).toEqual([
      'bypass_settings',
      { users: [{ id: 1 }], access_tokens: [{ id: 2 }] },
    ]);
  });

  it('omits a key entirely once its list is cleared', () => {
    createWrapper({ users: [{ id: 1 }], access_tokens: [{ id: 2 }] });
    findUsersSelector().vm.$emit('set-users', []);
    expect(wrapper.emitted('changed')[0]).toEqual([
      'bypass_settings',
      { access_tokens: [{ id: 2 }] },
    ]);
  });

  it('emits an empty object when both lists are cleared', () => {
    createWrapper({ users: [{ id: 1 }] });
    findUsersSelector().vm.$emit('set-users', []);
    expect(wrapper.emitted('changed')[0]).toEqual(['bypass_settings', {}]);
  });
});
