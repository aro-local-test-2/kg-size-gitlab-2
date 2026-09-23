import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlButton, GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { EMPTY_CATALOGS } from 'ee/policy_store/utils';
import { ACTIONS } from 'ee/policy_store/catalog/actions';
import { RULES } from 'ee/policy_store/catalog/rules';
import { TRIGGERS } from 'ee/policy_store/catalog/triggers';
import getPolicyStoreCatalogs from 'ee/policy_store/graphql/get_policy_store_catalogs.query.graphql';
import getGroupPolicyStoreCatalogs from 'ee/policy_store/graphql/get_group_policy_store_catalogs.query.graphql';
import StepWizard from 'ee/policy_store/components/editor/step_wizard.vue';
import BuildPolicyStep from 'ee/policy_store/components/editor/steps/build_policy_step.vue';
import ScopeStep from 'ee/policy_store/components/editor/steps/scope_step.vue';
import ReviewStep from 'ee/policy_store/components/editor/steps/review_step.vue';
import PolicyNameField from 'ee/policy_store/components/editor/policy_name_field.vue';
import WizardControls from 'ee/policy_store/components/editor/wizard_controls.vue';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

const ORGANIZATION_GID = 'gid://gitlab/Organizations::Organization/42';

const catalogsResponse = ({
  triggers = [{ id: 'deployment_requested', name: 'Deployment', __typename: 'PolicyStoreTrigger' }],
  rules = [{ id: 'custom', name: 'Custom', __typename: 'PolicyStoreRule' }],
  actions = [{ id: 'block', name: 'Block', __typename: 'PolicyStoreAction' }],
} = {}) => ({
  data: {
    organization: {
      id: ORGANIZATION_GID,
      __typename: 'Organization',
      policyStore: { triggers, rules, actions, __typename: 'PolicyStore' },
    },
  },
});

describe('StepWizard', () => {
  let wrapper;
  let catalogsHandler;

  const createComponent = (propsData = {}, provide = {}) => {
    wrapper = shallowMountExtended(StepWizard, {
      propsData,
      apolloProvider: createMockApollo([[getPolicyStoreCatalogs, catalogsHandler]]),
      provide: { organizationId: '42', namespaceType: 'organization', ...provide },
    });
  };

  beforeEach(() => {
    catalogsHandler = jest.fn().mockResolvedValue(catalogsResponse());
  });

  const findNameField = () => wrapper.findComponent(PolicyNameField);
  const findControls = () => wrapper.findComponent(WizardControls);
  const findStepContent = () => wrapper.findByTestId('wizard-step-content');
  const findBuildStep = () => wrapper.findComponent(BuildPolicyStep);
  const findModal = () => wrapper.findComponent(GlModal);
  const findScopeStep = () => wrapper.findComponent(ScopeStep);
  const findButtonByText = (text) =>
    wrapper.findAllComponents(GlButton).wrappers.find((button) => button.text() === text);

  const stepStatuses = () =>
    findControls()
      .props('steps')
      .map(({ status }) => status);

  it('starts with an empty name for a new policy', () => {
    createComponent();

    expect(findNameField().props('name')).toBe('');
  });

  it('seeds name and description from an existing policy', () => {
    createComponent({ policy: { name: 'My policy', description: 'Some description' } });

    expect(findNameField().props('name')).toBe('My policy');
    expect(findNameField().props('description')).toBe('Some description');
  });

  it('forwards the name error to the name field', () => {
    createComponent({ nameError: 'A policy with this name already exists.' });

    expect(findNameField().props('error')).toBe('A policy with this name already exists.');
  });

  it('emits name-update when the name is edited, so the error can be cleared', async () => {
    createComponent({ nameError: 'A policy with this name already exists.' });

    await findNameField().vm.$emit('update:name', 'Fresh name');

    expect(wrapper.emitted('name-update')).toHaveLength(1);
  });

  it('does not emit name-update when only the description is edited', async () => {
    createComponent({ nameError: 'A policy with this name already exists.' });

    await findNameField().vm.$emit('update:description', 'New description');

    expect(wrapper.emitted('name-update')).toBeUndefined();
  });

  it('renders the steps in order with the first step current', () => {
    createComponent();

    expect(
      findControls()
        .props('steps')
        .map(({ label }) => label),
    ).toEqual(['Build policy', 'Select scope', 'Review impact']);
    expect(stepStatuses()).toEqual(['current', 'upcoming', 'upcoming']);
    expect(findBuildStep().exists()).toBe(true);
  });

  it('marks only the last step as last, which ends the connector line', () => {
    createComponent();

    expect(
      findControls()
        .props('steps')
        .map(({ isLast }) => isLast),
    ).toEqual([false, false, true]);
  });

  it('completes a step once it has been passed', async () => {
    createComponent();

    await findButtonByText('Next').vm.$emit('click');

    expect(stepStatuses()).toEqual(['complete', 'current', 'upcoming']);
  });

  it('keeps the header above the content on every step', async () => {
    createComponent();

    expect(findNameField().exists()).toBe(true);
    expect(findControls().exists()).toBe(true);

    await findButtonByText('Next').vm.$emit('click');

    expect(findNameField().exists()).toBe(true);
    expect(findControls().exists()).toBe(true);
    expect(findBuildStep().exists()).toBe(false);
  });

  it('renders the scope step when advancing to it', async () => {
    createComponent();

    expect(findScopeStep().exists()).toBe(false);

    await findButtonByText('Next').vm.$emit('click');

    expect(findScopeStep().exists()).toBe(true);
  });

  // The wizard always sends a mode, so its proposed default is what a new
  // policy saves as; it has to match the store's own default of warn.
  it('renders the enforcement mode selector defaulting to Warn', () => {
    createComponent();

    expect(findControls().props('mode')).toBe('warn');
  });

  it('keeps the mode of a policy being edited instead of the default', () => {
    createComponent({ policy: { mode: 'enforce' } });

    expect(findControls().props('mode')).toBe('enforce');
  });

  it('queries the catalogs for the organization once and passes them to the steps', async () => {
    createComponent();
    await waitForPromises();

    expect(catalogsHandler).toHaveBeenCalledTimes(1);
    expect(catalogsHandler).toHaveBeenCalledWith({ id: ORGANIZATION_GID });

    const catalogs = {
      triggers: [TRIGGERS.find(({ id }) => id === 'deployment_requested')],
      rules: [RULES.find(({ id }) => id === 'custom')],
      actions: [ACTIONS.find(({ id }) => id === 'block')],
    };
    expect(findBuildStep().props('catalogs')).toEqual(catalogs);

    await findButtonByText('Next').vm.$emit('click');
    await findButtonByText('Next').vm.$emit('click');

    expect(wrapper.findComponent(ReviewStep).props('catalogs')).toEqual(catalogs);
  });

  it('marks the catalogs as loading while the query is in flight and disables Next', async () => {
    catalogsHandler = jest.fn().mockReturnValue(new Promise(() => {}));

    createComponent();

    // First render, before any tick: a late-arriving loading state would
    // flash the empty state instead of the skeleton.
    expect(findBuildStep().props('catalogsLoading')).toBe(true);

    await nextTick();

    expect(findBuildStep().props('catalogsLoading')).toBe(true);
    expect(findBuildStep().props('catalogs')).toBe(EMPTY_CATALOGS);
    expect(findButtonByText('Next').props('disabled')).toBe(true);
  });

  it('ends the loading state and enables Next once the query resolves', async () => {
    createComponent();
    await waitForPromises();

    expect(findBuildStep().props('catalogsLoading')).toBe(false);
    expect(findBuildStep().props('failedCatalogs')).toEqual([]);
    expect(findButtonByText('Next').props('disabled')).toBe(false);
  });

  it('passes the failing catalogs alongside the partial results', async () => {
    catalogsHandler = jest.fn().mockResolvedValue(catalogsResponse({ triggers: [] }));

    createComponent();
    await waitForPromises();

    expect(findBuildStep().props('failedCatalogs')).toEqual(['triggers']);
    expect(findBuildStep().props('catalogs')).toEqual({
      triggers: [],
      rules: [RULES.find(({ id }) => id === 'custom')],
      actions: [ACTIONS.find(({ id }) => id === 'block')],
    });
    expect(findBuildStep().props('catalogsLoading')).toBe(false);
  });

  it('treats a query error as all catalogs failing and reports it', async () => {
    catalogsHandler = jest.fn().mockRejectedValue(new Error('request failed'));

    createComponent();
    await waitForPromises();

    expect(findBuildStep().props('failedCatalogs')).toEqual(['triggers', 'rules', 'actions']);
    expect(findBuildStep().props('catalogs')).toEqual(EMPTY_CATALOGS);
    expect(findBuildStep().props('catalogsLoading')).toBe(false);
    expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error), {
      tags: { policyStoreCatalog: 'all' },
    });
  });

  it('fails every catalog when the organization is not accessible', async () => {
    catalogsHandler = jest.fn().mockResolvedValue({ data: { organization: null } });

    createComponent();
    await waitForPromises();

    expect(findBuildStep().props('failedCatalogs')).toEqual(['triggers', 'rules', 'actions']);
    expect(findBuildStep().props('catalogs')).toEqual(EMPTY_CATALOGS);
    expect(findBuildStep().props('catalogsLoading')).toBe(false);
  });

  describe('without an organization id', () => {
    beforeEach(() => {
      createComponent({}, { organizationId: '', namespaceType: 'organization' });
    });

    it('never queries the catalogs', async () => {
      await waitForPromises();

      expect(catalogsHandler).not.toHaveBeenCalled();
    });

    it('starts settled with every catalog failed instead of loading forever', () => {
      expect(findBuildStep().props('catalogsLoading')).toBe(false);
      expect(findBuildStep().props('catalogs')).toBe(EMPTY_CATALOGS);
      expect(findBuildStep().props('failedCatalogs')).toEqual(['triggers', 'rules', 'actions']);
    });
  });

  it('goes back to the previous step when Back is clicked', async () => {
    createComponent();

    await findButtonByText('Next').vm.$emit('click');
    await findButtonByText('Back').vm.$emit('click');

    expect(findBuildStep().exists()).toBe(true);
  });

  describe('build step', () => {
    it('renders the build step rather than a placeholder for the first step', () => {
      createComponent();

      expect(findBuildStep().exists()).toBe(true);
      expect(findStepContent().text()).not.toContain('coming soon');
    });

    it('starts with empty policy data for a new policy', () => {
      createComponent();

      expect(findBuildStep().props('policyData')).toEqual({
        trigger: null,
        triggerConfig: {},
        rules: [],
        ruleConfigs: {},
        actions: [],
        actionConfigs: {},
      });
    });

    it('seeds policy data from an existing policy', () => {
      createComponent({
        policy: {
          name: 'Prod gate',
          trigger_type: 'deployment_requested',
          rules: [{ type: 'custom', value: 'package governance' }],
          actions: [{ type: 'block' }],
        },
      });

      expect(findBuildStep().props('policyData')).toMatchObject({
        trigger: 'deployment_requested',
        rules: ['custom'],
        ruleConfigs: { custom: { policy: 'package governance' } },
        actions: ['block'],
      });
    });

    it('keeps policy data when navigating away and back', async () => {
      createComponent();

      findBuildStep().vm.$emit('update', {
        trigger: 'deployment_requested',
        triggerConfig: {},
        rules: ['custom'],
        ruleConfigs: {},
        actions: [],
        actionConfigs: {},
      });
      await findButtonByText('Next').vm.$emit('click');
      await findButtonByText('Back').vm.$emit('click');

      expect(findBuildStep().props('policyData')).toMatchObject({
        trigger: 'deployment_requested',
        rules: ['custom'],
      });
    });
  });

  it('hides Back on the first step and Next on the last step', async () => {
    createComponent();

    expect(findButtonByText('Back')).toBeUndefined();

    await findButtonByText('Next').vm.$emit('click');
    await findButtonByText('Next').vm.$emit('click');

    expect(findButtonByText('Next')).toBeUndefined();
    expect(findButtonByText('Back')).toBeDefined();
  });

  it('renders the review step on the last step seeded with the policy name', async () => {
    createComponent({ policy: { name: 'My policy' } });

    expect(wrapper.findComponent(ReviewStep).exists()).toBe(false);

    await findButtonByText('Next').vm.$emit('click');
    await findButtonByText('Next').vm.$emit('click');

    expect(wrapper.findComponent(ReviewStep).props('policy').name).toBe('My policy');
  });

  it('passes the mode, scope, and Build step selections to the review step', async () => {
    createComponent({
      policy: {
        name: 'My policy',
        mode: 'warn',
        policy_scope: { projects: { including: [1] } },
        trigger_type: 'deployment_requested',
        rules: [{ type: 'custom', value: 'package x' }],
        actions: [{ type: 'block' }],
      },
    });

    await findButtonByText('Next').vm.$emit('click');
    await findButtonByText('Next').vm.$emit('click');

    expect(wrapper.findComponent(ReviewStep).props('policy')).toMatchObject({
      mode: 'warn',
      scope: { mode: 'specific', projects: [{ id: 'gid://gitlab/Project/1' }] },
      trigger: 'deployment_requested',
      rules: ['custom'],
      actions: ['block'],
    });
  });

  describe('save button', () => {
    const findSaveButton = () => wrapper.findComponentByTestId('save-policy-button');
    const savablePolicy = {
      name: 'Prod gate',
      trigger_type: 'deployment_requested',
      rules: [{ type: 'custom', value: 'package governance' }],
    };

    const goToLastStep = async () => {
      await findButtonByText('Next').vm.$emit('click');
      await findButtonByText('Next').vm.$emit('click');
    };

    it('does not render before the last step', () => {
      createComponent();

      expect(findSaveButton().exists()).toBe(false);
    });

    it('is disabled while the policy lacks a name, trigger or rule', async () => {
      createComponent();
      await goToLastStep();

      expect(findSaveButton().props('disabled')).toBe(true);
    });

    it('is enabled once the policy has a name, a trigger and a rule', async () => {
      createComponent({ policy: savablePolicy });
      await goToLastStep();

      expect(findSaveButton().props('disabled')).toBe(false);
    });

    it('is disabled while a selected rule is missing its required config', async () => {
      createComponent({
        policy: { ...savablePolicy, rules: [{ type: 'custom', value: '' }] },
      });
      await goToLastStep();

      expect(findSaveButton().props('disabled')).toBe(true);
      expect(wrapper.findComponent(ReviewStep).props('saveBlockers')).toEqual([
        'Custom Rule (Rego) is missing Rego policy definition.',
      ]);
    });

    it('is disabled while an environment rule names neither environments nor tiers', async () => {
      createComponent({
        policy: { ...savablePolicy, rules: [{ type: 'environment', value: {} }] },
      });
      await goToLastStep();

      expect(findSaveButton().props('disabled')).toBe(true);
      expect(wrapper.findComponent(ReviewStep).props('saveBlockers')).toEqual([
        'Environment State needs at least one of: Environment names, Environment tiers.',
      ]);
    });

    it('emits save with everything the wizard edits', async () => {
      createComponent({ policy: savablePolicy });
      await goToLastStep();

      findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')).toEqual([
        [
          {
            name: 'Prod gate',
            description: '',
            mode: 'warn',
            scope: { mode: 'all', projects: [], exclusions: [] },
            scopeChanged: false,
            policyData: expect.objectContaining({
              trigger: 'deployment_requested',
              rules: ['custom'],
            }),
          },
        ],
      ]);
    });

    it('reports the scope as changed once the Scope step is touched', async () => {
      createComponent({ policy: savablePolicy });
      await findButtonByText('Next').vm.$emit('click');

      await findScopeStep().vm.$emit('update', {
        mode: 'specific',
        projects: [{ id: 'gid://gitlab/Project/1' }],
        exclusions: [],
      });
      await findButtonByText('Next').vm.$emit('click');

      findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')[0][0]).toMatchObject({
        scopeChanged: true,
        scope: { mode: 'specific', projects: [{ id: 'gid://gitlab/Project/1' }] },
      });
    });

    it('shows as loading while the save is in flight', async () => {
      createComponent({ policy: savablePolicy, saving: true });
      await goToLastStep();

      expect(findSaveButton().props('loading')).toBe(true);
    });
  });

  it('returns to the first step when the review step emits edit', async () => {
    createComponent();
    await findButtonByText('Next').vm.$emit('click');
    await findButtonByText('Next').vm.$emit('click');

    await wrapper.findComponent(ReviewStep).vm.$emit('edit');

    expect(findBuildStep().exists()).toBe(true);
    expect(wrapper.findComponent(ReviewStep).exists()).toBe(false);
  });

  it('emits cancel immediately when there are no unsaved changes', () => {
    createComponent();

    findButtonByText('Cancel').vm.$emit('click');

    expect(findModal().props('visible')).toBe(false);
    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });

  it('confirms before discarding when the name has changed', async () => {
    createComponent();

    await findNameField().vm.$emit('update:name', 'My new policy');
    await findButtonByText('Cancel').vm.$emit('click');

    expect(findModal().props('visible')).toBe(true);
    expect(wrapper.emitted('cancel')).toBeUndefined();
  });

  it('emits cancel when the discard action is confirmed', async () => {
    createComponent();
    await findNameField().vm.$emit('update:name', 'My new policy');
    await findButtonByText('Cancel').vm.$emit('click');

    findModal().vm.$emit('primary');

    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });

  describe('leaving the page with unsaved changes', () => {
    const dispatchBeforeUnload = () => {
      const event = new Event('beforeunload', { cancelable: true });
      window.dispatchEvent(event);
      return event;
    };

    it('prompts before unloading when there are unsaved changes', async () => {
      createComponent();
      await findNameField().vm.$emit('update:name', 'My new policy');

      expect(dispatchBeforeUnload().defaultPrevented).toBe(true);
    });

    it('does not prompt when nothing has changed', () => {
      createComponent();

      expect(dispatchBeforeUnload().defaultPrevented).toBe(false);
    });

    it('does not prompt while the save-triggered navigation is in flight', async () => {
      createComponent({ saving: true });
      await findNameField().vm.$emit('update:name', 'My new policy');

      expect(dispatchBeforeUnload().defaultPrevented).toBe(false);
    });

    it('does not prompt again after the discard was confirmed', async () => {
      createComponent();
      await findNameField().vm.$emit('update:name', 'My new policy');
      await findButtonByText('Cancel').vm.$emit('click');

      findModal().vm.$emit('primary');

      expect(dispatchBeforeUnload().defaultPrevented).toBe(false);
    });

    it('stops guarding once the wizard is destroyed', async () => {
      createComponent();
      await findNameField().vm.$emit('update:name', 'My new policy');

      wrapper.destroy();

      expect(dispatchBeforeUnload().defaultPrevented).toBe(false);
    });
  });

  it('leaves immediately when an existing policy is opened and left unchanged', () => {
    createComponent({ policy: { name: 'My policy', description: 'Some description' } });

    findButtonByText('Cancel').vm.$emit('click');

    expect(findModal().props('visible')).toBe(false);
    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });

  it('leaves immediately on cancel after only advancing a step', async () => {
    createComponent();
    await findButtonByText('Next').vm.$emit('click');

    findButtonByText('Cancel').vm.$emit('click');

    expect(findModal().props('visible')).toBe(false);
    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });

  it('confirms before discarding when the enforcement mode has changed', async () => {
    createComponent();

    await findControls().vm.$emit('select-mode', 'audit');
    await findButtonByText('Cancel').vm.$emit('click');

    expect(findModal().props('visible')).toBe(true);
    expect(wrapper.emitted('cancel')).toBeUndefined();
  });

  it('confirms before discarding when the scope has changed', async () => {
    createComponent();
    await findButtonByText('Next').vm.$emit('click');

    await findScopeStep().vm.$emit('update', { mode: 'specific', projects: [{ id: '1' }] });
    await findButtonByText('Cancel').vm.$emit('click');

    expect(findModal().props('visible')).toBe(true);
    expect(wrapper.emitted('cancel')).toBeUndefined();
  });

  it('confirms before discarding when the Build step selections have changed', async () => {
    createComponent();

    await findBuildStep().vm.$emit('update', {
      trigger: null,
      triggerConfig: {},
      rules: ['custom'],
      ruleConfigs: {},
      actions: [],
      actionConfigs: {},
    });
    await findButtonByText('Cancel').vm.$emit('click');

    expect(findModal().props('visible')).toBe(true);
    expect(wrapper.emitted('cancel')).toBeUndefined();
  });

  describe('in group context', () => {
    const groupCatalogsResponse = ({
      triggers = [
        { id: 'deployment_requested', name: 'Deployment', __typename: 'PolicyStoreTrigger' },
      ],
      rules = [{ id: 'custom', name: 'Custom', __typename: 'PolicyStoreRule' }],
      actions = [{ id: 'block', name: 'Block', __typename: 'PolicyStoreAction' }],
    } = {}) => ({
      data: {
        group: {
          id: 'gid://gitlab/Group/123',
          __typename: 'Group',
          policyStore: { triggers, rules, actions, __typename: 'PolicyStore' },
        },
      },
    });

    let groupCatalogsHandler;

    const createGroupComponent = (propsData = {}, provide = {}) => {
      wrapper = shallowMountExtended(StepWizard, {
        propsData,
        apolloProvider: createMockApollo([[getGroupPolicyStoreCatalogs, groupCatalogsHandler]]),
        provide: {
          namespaceType: 'group',
          namespacePath: 'my-org/my-group',
          organizationId: '',
          ...provide,
        },
      });
    };

    beforeEach(() => {
      groupCatalogsHandler = jest.fn().mockResolvedValue(groupCatalogsResponse());
    });

    it('queries the group catalogs with fullPath instead of organization id', async () => {
      createGroupComponent();
      await waitForPromises();

      expect(groupCatalogsHandler).toHaveBeenCalledTimes(1);
      expect(groupCatalogsHandler).toHaveBeenCalledWith({ fullPath: 'my-org/my-group' });
    });

    it('passes catalogs from the group response to the build step', async () => {
      createGroupComponent();
      await waitForPromises();

      const catalogs = {
        triggers: [TRIGGERS.find(({ id }) => id === 'deployment_requested')],
        rules: [RULES.find(({ id }) => id === 'custom')],
        actions: [ACTIONS.find(({ id }) => id === 'block')],
      };
      expect(findBuildStep().props('catalogs')).toEqual(catalogs);
    });

    it('fails every catalog when mounted without a namespacePath', () => {
      createGroupComponent({}, { namespacePath: '' });

      expect(findBuildStep().props('catalogsLoading')).toBe(false);
      expect(findBuildStep().props('catalogs')).toBe(EMPTY_CATALOGS);
      expect(findBuildStep().props('failedCatalogs')).toEqual(['triggers', 'rules', 'actions']);
    });

    it('treats a query error as all catalogs failing', async () => {
      groupCatalogsHandler = jest.fn().mockRejectedValue(new Error('request failed'));

      createGroupComponent();
      await waitForPromises();

      expect(findBuildStep().props('failedCatalogs')).toEqual(['triggers', 'rules', 'actions']);
      expect(findBuildStep().props('catalogs')).toEqual(EMPTY_CATALOGS);
      expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error), {
        tags: { policyStoreCatalog: 'all' },
      });
    });
  });
});
