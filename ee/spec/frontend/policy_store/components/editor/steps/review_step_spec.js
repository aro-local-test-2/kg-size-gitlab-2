import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ReviewStep from 'ee/policy_store/components/editor/steps/review_step.vue';
import { ACTIONS } from 'ee/policy_store/catalog/actions';
import { RULES } from 'ee/policy_store/catalog/rules';
import { TRIGGERS } from 'ee/policy_store/catalog/triggers';

describe('ReviewStep', () => {
  let wrapper;

  const createComponent = (propsData = {}) => {
    wrapper = shallowMountExtended(ReviewStep, { propsData });
  };

  const findRow = (testid) => wrapper.findByTestId(testid);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findEdit = () => wrapper.findComponentByTestId('edit-policy');

  it('shows the policy name, falling back to a dash when empty', () => {
    createComponent();
    expect(findRow('detail-name').text()).toContain('—');

    createComponent({ policy: { name: 'My policy' } });
    expect(findRow('detail-name').text()).toContain('My policy');
  });

  // The store defaults an unset mode to warn, so the review step has to show
  // warn rather than proposing the stricter mode the wizard would then save.
  it('defaults the mode to Warn with a matching warning alert', () => {
    createComponent();

    expect(findRow('detail-mode').text()).toContain('Warn');
    expect(findAlert().props('variant')).toBe('warning');
    expect(findAlert().text()).toContain('Warn mode');
  });

  it('interpolates the scope into the alert in lowercase mid-sentence', () => {
    createComponent();

    expect(findAlert().text()).toContain('enabled for all projects in the group in Warn mode');
  });

  it('reflects an enforce mode in the row and the alert', () => {
    createComponent({ policy: { mode: 'enforce' } });

    expect(findRow('detail-mode').text()).toContain('Enforce');
    expect(findAlert().props('variant')).toBe('danger');
  });

  // An unknown mode cannot come from the wizard, but it can come from a policy
  // saved by a newer catalog; it falls back to the default rather than blanking.
  it('falls back to the default mode when the catalog does not know the value', () => {
    createComponent({ policy: { mode: 'brand_new_mode' } });

    expect(findRow('detail-mode').text()).toContain('Warn');
    expect(findAlert().props('variant')).toBe('warning');
  });

  it('reflects an audit mode in the row and the alert', () => {
    createComponent({ policy: { mode: 'audit' } });

    expect(findRow('detail-mode').text()).toContain('Audit');
    expect(findAlert().props('variant')).toBe('info');
  });

  it('shows all projects scope by default', () => {
    createComponent();

    expect(findRow('detail-scope').text()).toContain('Default (all projects)');
    expect(findRow('detail-projects').text()).toContain('All projects in the group');
  });

  it('shows a targeted scope with the project count', () => {
    createComponent({ policy: { scope: { mode: 'specific', projects: [1, 2, 3] } } });

    expect(findRow('detail-scope').text()).toContain('Targeted');
    expect(findRow('detail-projects').text()).toContain('3 projects');
  });

  it('summarises empty triggers, rules, and actions as None added', () => {
    createComponent();

    expect(findRow('config-triggers').text()).toContain('None added');
    expect(findRow('config-rules').text()).toContain('None added');
    expect(findRow('config-actions').text()).toContain('None added');
  });

  it('summarises the selections using their catalog labels', () => {
    createComponent({
      policy: {
        trigger: 'deployment_requested',
        rules: ['custom', 'calendar'],
        actions: ['block'],
      },
      catalogs: { triggers: TRIGGERS, rules: RULES, actions: ACTIONS },
    });

    expect(findRow('config-triggers').text()).toContain('Deployment');
    expect(findRow('config-rules').text()).toContain('Custom Rule (Rego), Freeze Window');
    expect(findRow('config-actions').text()).toContain('Block');
  });

  it('labels the selections from the catalogs prop', () => {
    createComponent({
      policy: { rules: ['calendar'] },
      catalogs: {
        triggers: [],
        rules: [{ id: 'calendar', label: 'Calendar', description: '', icon: 'clock', fields: [] }],
        actions: [],
      },
    });

    expect(findRow('config-rules').text()).toContain('Calendar');
  });

  it('falls back to the raw id when the catalog no longer knows it', () => {
    createComponent({ policy: { rules: ['retired_rule'] } });

    expect(findRow('config-rules').text()).toContain('retired_rule');
  });

  it('emits edit when the Edit policy button is clicked', () => {
    createComponent();

    findEdit().vm.$emit('click');

    expect(wrapper.emitted('edit')).toHaveLength(1);
  });

  describe('save blockers', () => {
    const blockers = ['Custom Rule (Rego) is missing Rego policy definition.'];

    it('lists each blocker while keeping the impact statement visible', () => {
      createComponent({ saveBlockers: blockers });

      const alert = wrapper.findComponentByTestId('save-blockers');
      expect(alert.props('title')).toBe('Complete the policy before saving');
      expect(alert.text()).toContain(blockers[0]);
      expect(wrapper.findComponentByTestId('impact-alert').exists()).toBe(true);
    });

    it('renders no blockers alert when there is nothing to fix', () => {
      createComponent();

      expect(wrapper.findComponentByTestId('save-blockers').exists()).toBe(false);
      expect(wrapper.findComponentByTestId('impact-alert').exists()).toBe(true);
    });
  });
});
