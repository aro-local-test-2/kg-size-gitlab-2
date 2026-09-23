import VueApollo from 'vue-apollo';
import Vue, { nextTick } from 'vue';
import { GlToggle } from '@gitlab/ui';

import SettingsBlock from '~/vue_shared/components/settings/settings_block.vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import PolicyStoreSettings from 'ee/organizations/settings/general/components/policy_store_settings.vue';
import organizationUpdateMutation from '~/organizations/settings/general/graphql/mutations/organization_update.mutation.graphql';
import { createAlert } from '~/alert';
import { scrollUp } from '~/lib/utils/scroll_utils';

Vue.use(VueApollo);

jest.mock('~/alert');
jest.mock('~/lib/utils/scroll_utils', () => ({
  scrollUp: jest.fn(),
}));

describe('PolicyStoreSettings', () => {
  let wrapper;

  const successResponse = {
    data: {
      organizationUpdate: {
        organization: {
          id: 'gid://gitlab/Organizations::Organization/1',
          name: 'First',
          path: 'first',
          webUrl: 'http://gdk.test/o/first',
        },
        errors: [],
      },
    },
  };
  const errorResponse = {
    data: {
      organizationUpdate: {
        organization: null,
        errors: ['You have insufficient permissions to update the organization'],
      },
    },
  };

  const successHandler = jest.fn().mockResolvedValue(successResponse);

  const createComponent = ({ handler = successHandler, provide = {}, propsData = {} } = {}) => {
    wrapper = shallowMountExtended(PolicyStoreSettings, {
      apolloProvider: createMockApollo([[organizationUpdateMutation, handler]]),
      propsData: {
        id: 'organization-settings-policy-store',
        expanded: false,
        ...propsData,
      },
      provide: {
        organization: { id: 1 },
        policyStoreExperimentEnabled: false,
        ...provide,
      },
    });
  };

  const findToggle = () => wrapper.findComponent(GlToggle);
  const findSettingsBlock = () => wrapper.findComponent(SettingsBlock);

  it('forwards the section id and expand state to the settings block', () => {
    createComponent({ propsData: { expanded: true } });

    expect(findSettingsBlock().props('id')).toBe('organization-settings-policy-store');
    expect(findSettingsBlock().props('expanded')).toBe(true);
  });

  it('re-emits toggle-expand from the settings block', () => {
    createComponent();

    findSettingsBlock().vm.$emit('toggle-expand', true);

    expect(wrapper.emitted('toggle-expand')).toEqual([[true]]);
  });

  it('renders the toggle with the injected value', () => {
    createComponent({ provide: { policyStoreExperimentEnabled: true } });

    expect(findToggle().props('value')).toBe(true);
  });

  it('reads an absent setting as disabled', () => {
    createComponent({ provide: { policyStoreExperimentEnabled: null } });

    expect(findToggle().props('value')).toBe(false);
  });

  describe('when the toggle is flipped', () => {
    it('sends the setting through organizationUpdate and confirms', async () => {
      createComponent();

      findToggle().vm.$emit('change', true);
      await waitForPromises();

      expect(successHandler).toHaveBeenCalledWith({
        input: {
          id: 'gid://gitlab/Organizations::Organization/1',
          policyStoreExperimentEnabled: true,
        },
      });
      expect(findToggle().props('value')).toBe(true);
      expect(findToggle().props('disabled')).toBe(false);
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Policy store experiment setting updated.',
        variant: 'info',
      });
      expect(scrollUp).toHaveBeenCalled();
    });

    it('disables the toggle and keeps its value while the mutation is in flight', async () => {
      createComponent();

      findToggle().vm.$emit('change', true);
      await nextTick();

      expect(findToggle().props('disabled')).toBe(true);
      expect(findToggle().props('isLoading')).toBe(true);
      expect(findToggle().props('value')).toBe(false);

      await waitForPromises();
    });

    it('leaves the toggle off when the mutation returns errors', async () => {
      createComponent({ handler: jest.fn().mockResolvedValue(errorResponse) });

      findToggle().vm.$emit('change', true);
      await waitForPromises();

      expect(findToggle().props('value')).toBe(false);
      expect(createAlert).toHaveBeenCalledWith({
        message: 'You have insufficient permissions to update the organization',
      });
    });

    it('leaves the toggle off when the request fails', async () => {
      const error = new Error('network');

      createComponent({ handler: jest.fn().mockRejectedValue(error) });

      findToggle().vm.$emit('change', true);
      await waitForPromises();

      expect(findToggle().props('value')).toBe(false);
      expect(createAlert).toHaveBeenCalledWith({
        message: 'An error occurred updating the Policy store setting. Please try again.',
        error,
        captureError: true,
      });
    });
  });
});
