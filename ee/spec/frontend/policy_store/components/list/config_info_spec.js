import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ConfigInfo from 'ee/policy_store/components/list/config_info.vue';
import ConfigInfoSection from 'ee/policy_store/components/list/config_info_section.vue';

describe('PolicyConfigInfo', () => {
  let wrapper;

  const policy = {
    id: 1,
    mode: 'enforce',
    status: 'active',
    trigger_type: 'deployment_requested',
    rules: [
      {
        type: 'calendar',
        value: {
          windows: [
            {
              name: 'Year end',
              tiers: ['production'],
              starts_at: '2026-12-20T00:00:00Z',
              ends_at: '2027-01-02T00:00:00Z',
            },
          ],
        },
      },
    ],
    actions: [{ type: 'require_approval', value: { roles: ['maintainer'] } }],
  };

  const createComponent = (policyData = policy) => {
    wrapper = shallowMountExtended(ConfigInfo, { propsData: { policy: policyData } });
  };

  const findByTestId = (id) => wrapper.findByTestId(id);
  const findSections = () => wrapper.findAllComponents(ConfigInfoSection);
  const findRulesSection = () => findSections().at(0);
  const findActionsSection = () => findSections().at(1);

  it('shows the mode with its plain-language description', () => {
    createComponent();

    expect(findByTestId('config-info-mode').text()).toBe('Enforce');
    expect(findByTestId('config-info-mode-description').text()).toBe(
      'Enforce the action when rules match',
    );
  });

  it('shows the enabled state alongside the other config info', () => {
    createComponent({ ...policy, status: 'disabled' });

    expect(findByTestId('config-info-status').text()).toBe('Disabled');
  });

  it('hands each section its label, empty label, and testid', () => {
    createComponent();

    expect(findRulesSection().props()).toMatchObject({
      testid: 'config-info-rules',
      label: 'Rules',
      emptyLabel: 'No rules configured',
    });
    expect(findActionsSection().props()).toMatchObject({
      testid: 'config-info-actions',
      label: 'Actions',
      emptyLabel: 'No actions configured',
    });
  });

  it('resolves rules and actions through the catalog into section entries', () => {
    createComponent();

    expect(findRulesSection().props('entries')).toMatchObject([
      {
        id: 'calendar',
        label: 'Freeze Window',
        description: 'Block deployments during configured freeze periods',
        configItems: [
          {
            label: 'Freeze windows',
            value: 'Year end · Production · 2026-12-20T00:00:00Z → 2027-01-02T00:00:00Z',
          },
        ],
      },
    ]);
    expect(findActionsSection().props('entries')).toMatchObject([
      {
        id: 'require_approval',
        label: 'Require approval',
        configItems: [{ label: 'Role approvers', value: 'Maintainer' }],
      },
    ]);
  });

  it('passes empty entry lists when nothing is configured', () => {
    createComponent({ ...policy, rules: [], actions: [] });

    expect(findRulesSection().props('entries')).toEqual([]);
    expect(findActionsSection().props('entries')).toEqual([]);
  });
});
