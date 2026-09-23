import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import App from 'ee/organizations/settings/general/components/app.vue';
import PolicyStoreSettings from 'ee/organizations/settings/general/components/policy_store_settings.vue';
import CeApp from '~/organizations/settings/general/components/app.vue';

describe('OrganizationSettingsGeneralAppEE', () => {
  let wrapper;

  const createComponent = ({ policyStoreExperimentAvailable = true } = {}) => {
    wrapper = shallowMountExtended(App, {
      provide: { policyStoreExperimentAvailable },
      // The real CE component so the slot contract is tested; its own
      // sections stay auto-stubbed under shallowMount.
      stubs: {
        CeOrganizationSettingsGeneralApp: CeApp,
      },
    });
  };

  const findPolicyStoreSettings = () => wrapper.findComponent(PolicyStoreSettings);

  it('renders the CE settings app', () => {
    createComponent();

    expect(wrapper.findComponent(CeApp).exists()).toBe(true);
  });

  it('renders the Policy Store section inside the CE app when the experiment is available', () => {
    createComponent();

    expect(wrapper.findComponent(CeApp).findComponent(PolicyStoreSettings).exists()).toBe(true);
    expect(findPolicyStoreSettings().props('id')).toBe('organization-settings-policy-store');
  });

  it('hides the Policy Store section when the experiment is not available', () => {
    createComponent({ policyStoreExperimentAvailable: false });

    expect(findPolicyStoreSettings().exists()).toBe(false);
  });

  it('tracks the section expand state through the CE app so settings search can expand it', async () => {
    createComponent();

    expect(findPolicyStoreSettings().props('expanded')).toBe(false);

    findPolicyStoreSettings().vm.$emit('toggle-expand', true);
    await nextTick();

    expect(findPolicyStoreSettings().props('expanded')).toBe(true);
  });
});
