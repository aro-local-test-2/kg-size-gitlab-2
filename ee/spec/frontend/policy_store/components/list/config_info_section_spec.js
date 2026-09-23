import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ConfigInfoSection from 'ee/policy_store/components/list/config_info_section.vue';

describe('ConfigInfoSection', () => {
  let wrapper;

  const entry = {
    id: 'require_approval',
    label: 'Require approval',
    description: 'Require additional approvals before proceeding',
    configItems: [{ key: 'roles', label: 'Role approvers', value: 'Maintainer', code: false }],
  };

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(ConfigInfoSection, {
      propsData: {
        testid: 'config-info-actions',
        label: 'Actions',
        emptyLabel: 'No actions configured',
        entries: [entry],
        ...props,
      },
    });
  };

  it('renders the section label on the element carrying the testid', () => {
    createComponent();

    expect(wrapper.findByTestId('config-info-actions').text()).toContain('Actions');
  });

  it('tolerates an entry without configItems', () => {
    createComponent({ entries: [{ id: 'block', label: 'Block' }] });

    expect(wrapper.find('li').text()).toBe('Block');
  });

  it('shows the empty label instead of a list when there are no entries', () => {
    createComponent({ entries: [] });

    expect(wrapper.text()).toContain('No actions configured');
    expect(wrapper.find('ul').exists()).toBe(false);
  });

  it('renders each entry with its label, description, and config items', () => {
    createComponent();

    const text = wrapper.find('li').text();
    expect(text).toContain('Require approval');
    expect(text).toContain('Require additional approvals before proceeding');
    expect(text).toContain('Role approvers');
    expect(text).toContain('Maintainer');
  });

  it('omits the description and config list when an entry has neither', () => {
    createComponent({ entries: [{ id: 'block', label: 'Block', configItems: [] }] });

    const item = wrapper.find('li');
    expect(item.text()).toBe('Block');
    expect(item.find('dl').exists()).toBe(false);
  });

  it('renders a config value as code when the item asks for it', () => {
    createComponent({
      entries: [
        {
          ...entry,
          configItems: [{ key: 'policy', label: 'Rego', value: 'package governance', code: true }],
        },
      ],
    });

    expect(wrapper.find('code').text()).toBe('package governance');
  });
});
