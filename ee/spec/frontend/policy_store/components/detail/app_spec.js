import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMount } from '@vue/test-utils';
import { GlBadge, GlSprintf } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { stubComponent } from 'helpers/stub_component';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { createAlert } from '~/alert';
import { visitUrl } from '~/lib/utils/url_utility';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import App from 'ee/policy_store/components/detail/app.vue';
import SummarySection from 'ee/policy_store/components/detail/summary_section.vue';
import {
  fetchPolicy,
  updatePolicy,
  deletePolicy,
  NAMESPACE_TYPE_GROUP,
  NAMESPACE_TYPE_ORGANIZATION,
} from 'ee/policy_store/policies';
import { PolicyStoreMutationError } from 'ee/policy_store/utils';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/alert');
jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  visitUrl: jest.fn(),
}));
jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal');
jest.mock('ee/policy_store/policies', () => ({
  fetchPolicy: jest.fn(),
  updatePolicy: jest.fn(),
  deletePolicy: jest.fn(),
  NAMESPACE_TYPE_GROUP: 'group',
  NAMESPACE_TYPE_ORGANIZATION: 'organization',
}));

Vue.use(VueApollo);

describe('PolicyStoreDetailRoot', () => {
  let wrapper;

  const policy = {
    id: 7,
    name: 'Production gate',
    description: 'Gates production deployments',
    type: 'Deployment requested',
    trigger_type: 'deployment_requested',
    rules: [{ type: 'custom', value: 'package governance' }],
    actions: [{ type: 'block' }],
    mode: 'enforce',
    status: 'active',
    scopedProjectsCount: 3,
    version: 3,
    created_at: '2026-08-19T23:41:12.686Z',
    updated_at: '2026-08-20T09:12:44.120Z',
  };

  const createComponent = async (provide = {}) => {
    wrapper = shallowMount(App, {
      provide: {
        organizationId: '1',
        namespaceType: 'organization',
        policyId: '7',
        listPath: '/-/security/policy_store',
        editPath: '/-/security/policy_store/7/edit',
        ...provide,
      },
      stubs: {
        GlSprintf,
        SummarySection: stubComponent(SummarySection, {
          template: '<section><slot></slot></section>',
        }),
      },
      apolloProvider: createMockApollo([]),
    });
    await waitForPromises();
  };

  const findByTestId = (id) => wrapper.find(`[data-testid="${id}"]`);
  const findBadges = () => wrapper.findAllComponents(GlBadge);
  const findSections = () => wrapper.findAllComponents(SummarySection);
  const findSection = (testid) =>
    findSections().wrappers.find((section) => section.props('testid') === testid);
  const findDeleteButton = () => wrapper.findComponent('[data-testid="delete-policy-button"]');

  beforeEach(() => {
    fetchPolicy.mockResolvedValue(policy);
    updatePolicy.mockResolvedValue({ ...policy, status: 'disabled' });
    deletePolicy.mockResolvedValue();
    confirmAction.mockResolvedValue(true);
  });

  it('fetches the policy through the single-policy endpoint', async () => {
    await createComponent();

    expect(fetchPolicy).toHaveBeenCalledWith(NAMESPACE_TYPE_ORGANIZATION, '1', '7');
  });

  it('renders the header with name, badges, and description', async () => {
    await createComponent();

    expect(findByTestId('policy-name').text()).toBe('Production gate');
    expect(findByTestId('policy-description').text()).toBe('Gates production deployments');
    expect(findBadges().wrappers.map((badge) => badge.text())).toEqual([
      'Deployment requested',
      'Enforce',
      'Active',
    ]);
  });

  it('renders no description paragraph when the policy has none', async () => {
    fetchPolicy.mockResolvedValue({ ...policy, description: '' });

    await createComponent();

    expect(findByTestId('policy-description').exists()).toBe(false);
  });

  it('passes catalog-resolved entries to the trigger, rules, and actions sections', async () => {
    await createComponent();

    expect(findSections().wrappers.map((section) => section.props('label'))).toEqual([
      'Trigger',
      'Rules',
      'Actions',
      'Scope',
    ]);
    expect(findSection('trigger').props('entries')).toEqual([
      expect.objectContaining({ label: 'Deployment requested' }),
    ]);
    expect(findSection('rules').props('entries')).toEqual([
      expect.objectContaining({ label: 'Custom Rule (Rego)' }),
    ]);
    expect(findSection('actions').props('entries')).toEqual([
      expect.objectContaining({ label: 'Block' }),
    ]);
  });

  it('falls back to the raw id for an entry the catalog no longer knows', async () => {
    fetchPolicy.mockResolvedValue({ ...policy, rules: [{ type: 'retired_rule', value: {} }] });

    await createComponent();

    expect(findSection('rules').props('entries')).toEqual([
      expect.objectContaining({ id: 'retired_rule', label: 'retired_rule', icon: 'question-o' }),
    ]);
  });

  it('passes no entries for a section with nothing configured', async () => {
    fetchPolicy.mockResolvedValue({ ...policy, actions: [] });

    await createComponent();

    expect(findSection('actions').props('entries')).toEqual([]);
  });

  it('resolves configured values into labelled config items on each entry', async () => {
    fetchPolicy.mockResolvedValue({
      ...policy,
      rules: [
        { type: 'custom', value: 'input.vulnerabilities.critical == 0' },
        {
          type: 'calendar',
          value: {
            windows: [
              {
                name: 'eoq-freeze',
                tiers: ['production', 'staging'],
                starts_at: '2026-12-24T00:00:00Z',
                ends_at: '2027-01-02T00:00:00Z',
              },
            ],
          },
        },
      ],
      actions: [{ type: 'require_approval', value: { roles: ['maintainer', 'owner'] } }],
    });

    await createComponent();

    const [customRule, calendarRule] = findSection('rules').props('entries');
    expect(customRule.configItems).toEqual([
      expect.objectContaining({
        label: 'Rego policy definition',
        code: true,
        value: 'input.vulnerabilities.critical == 0',
      }),
    ]);
    expect(calendarRule.configItems).toEqual([
      expect.objectContaining({
        label: 'Freeze windows',
        value: 'eoq-freeze · Production / Staging · 2026-12-24T00:00:00Z → 2027-01-02T00:00:00Z',
      }),
    ]);
    expect(findSection('actions').props('entries')[0].configItems).toEqual([
      expect.objectContaining({ label: 'Role approvers', value: 'Maintainer, Owner' }),
    ]);
  });

  it('omits config items for fields the policy leaves unset', async () => {
    await createComponent();

    expect(findSection('trigger').props('entries')[0].configItems).toEqual([]);
    expect(findSection('actions').props('entries')[0].configItems).toEqual([]);
  });

  it('summarises the scope in a summary section from the scoped project count', async () => {
    await createComponent();

    expect(findSection('scope').props('label')).toBe('Scope');
    expect(findSection('scope').text()).toContain('3 projects');
  });

  it('labels an unscoped policy as applying to all projects', async () => {
    fetchPolicy.mockResolvedValue({ ...policy, scopedProjectsCount: 0 });

    await createComponent();

    expect(findSection('scope').text()).toContain('All projects');
  });

  describe('when the policy has compiled scope Rego', () => {
    beforeEach(async () => {
      fetchPolicy.mockResolvedValue({
        ...policy,
        scope_rego: 'package gitlab.scope\n\napplicable = true',
      });

      await createComponent();
    });

    it('shows it in a read-only code block', () => {
      expect(findSection('scope-rego').props('label')).toBe('Compiled scope Rego');
      expect(findSection('scope-rego').find('pre code').text()).toBe(
        'package gitlab.scope\n\napplicable = true',
      );
    });

    it('makes the scrollable code block focusable and named for keyboard users', () => {
      expect(findSection('scope-rego').find('pre').attributes()).toMatchObject({
        tabindex: '0',
        role: 'region',
        'aria-label': 'Compiled scope Rego',
      });
    });
  });

  describe('when the policy has no compiled scope Rego', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('omits the scope Rego section', () => {
      expect(findSection('scope-rego')).toBeUndefined();
    });
  });

  describe('when the policy has compiled policy Rego', () => {
    beforeEach(async () => {
      fetchPolicy.mockResolvedValue({
        ...policy,
        policy_rego: 'package governance\n\nviolation contains {"msg": "no"}',
      });

      await createComponent();
    });

    it('shows it in a read-only code block', () => {
      expect(findSection('policy-rego').props('label')).toBe('Compiled policy Rego');
      expect(findSection('policy-rego').find('pre code').text()).toBe(
        'package governance\n\nviolation contains {"msg": "no"}',
      );
    });

    it('makes the scrollable code block focusable and named for keyboard users', () => {
      expect(findSection('policy-rego').find('pre').attributes()).toMatchObject({
        tabindex: '0',
        role: 'region',
        'aria-label': 'Compiled policy Rego',
      });
    });
  });

  describe('when the policy has no compiled policy Rego', () => {
    beforeEach(async () => {
      fetchPolicy.mockResolvedValue({ ...policy, policy_rego: null });

      await createComponent();
    });

    it('omits the policy Rego section', () => {
      expect(findSection('policy-rego')).toBeUndefined();
    });
  });

  it('shows the version and the created and updated times', async () => {
    await createComponent();

    expect(findByTestId('policy-version').text()).toBe('Version 3');
    expect(findByTestId('policy-created-at').findComponent(TimeAgoTooltip).props('time')).toBe(
      '2026-08-19T23:41:12.686Z',
    );
    expect(findByTestId('policy-updated-at').findComponent(TimeAgoTooltip).props('time')).toBe(
      '2026-08-20T09:12:44.120Z',
    );
  });

  it('omits the timestamps the store did not set', async () => {
    fetchPolicy.mockResolvedValue({ ...policy, created_at: null, updated_at: null });

    await createComponent();

    expect(findByTestId('policy-created-at').exists()).toBe(false);
    expect(findByTestId('policy-updated-at').exists()).toBe(false);
  });

  it('omits the version when the store did not set one', async () => {
    fetchPolicy.mockResolvedValue({ ...policy, version: null });

    await createComponent();

    expect(findByTestId('policy-version').exists()).toBe(false);
  });

  it('omits the whole meta line when the store set none of its fields', async () => {
    fetchPolicy.mockResolvedValue({
      ...policy,
      version: null,
      created_at: null,
      updated_at: null,
    });

    await createComponent();

    expect(findByTestId('policy-meta').exists()).toBe(false);
  });

  it('links the edit button to the edit path', async () => {
    await createComponent();

    expect(findByTestId('edit-policy-button').attributes('href')).toBe(
      '/-/security/policy_store/7/edit',
    );
  });

  it('shows a loading icon instead of the page while the policy loads', () => {
    fetchPolicy.mockReturnValue(new Promise(() => {}));

    wrapper = shallowMount(App, {
      provide: {
        organizationId: '1',
        namespaceType: 'organization',
        policyId: '7',
        listPath: '',
        editPath: '',
      },
    });

    expect(findByTestId('policy-loading').exists()).toBe(true);
    expect(findByTestId('policy-name').exists()).toBe(false);
  });

  it('shows an error instead of the page when the policy fails to load', async () => {
    const error = new Error('not found');
    fetchPolicy.mockRejectedValue(error);

    await createComponent();

    expect(findByTestId('policy-error').text()).toContain(
      'The policy could not be loaded from the Policy Store API.',
    );
    expect(findByTestId('policy-name').exists()).toBe(false);
    expect(Sentry.captureException).toHaveBeenCalledWith(error);
  });

  describe('toggling the policy status', () => {
    const findToggleButton = () => wrapper.findComponent('[data-testid="toggle-status-button"]');

    const requestToggle = async () => {
      findToggleButton().vm.$emit('click');
      await waitForPromises();
    };

    it('offers Disable for an active policy and Enable for a disabled one', async () => {
      await createComponent();
      expect(findToggleButton().text()).toBe('Disable');

      fetchPolicy.mockResolvedValue({ ...policy, status: 'disabled' });
      await createComponent();
      expect(findToggleButton().text()).toBe('Enable');
    });

    it('disables an active policy and refreshes the badge without navigating', async () => {
      await createComponent();

      await requestToggle();

      expect(updatePolicy).toHaveBeenCalledWith({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: '1',
        policyId: '7',
        params: { lifecycle_state: 'disabled' },
      });
      expect(findByTestId('policy-status').text()).toBe('Disabled');
      expect(findToggleButton().text()).toBe('Enable');
      expect(visitUrl).not.toHaveBeenCalled();
    });

    it('keeps the compiled Rego and refreshes the version after a toggle', async () => {
      fetchPolicy.mockResolvedValue({
        ...policy,
        policy_rego: 'package governance\n\nviolation contains {"msg": "no"}',
      });
      updatePolicy.mockResolvedValue({
        ...policy,
        status: 'disabled',
        version: 4,
        updated_at: '2026-08-20T20:00:00.000Z',
        policy_rego: 'package governance\n\nviolation contains {"msg": "no"}',
      });
      await createComponent();

      await requestToggle();

      expect(findSection('policy-rego').find('pre code').text()).toBe(
        'package governance\n\nviolation contains {"msg": "no"}',
      );
      expect(findByTestId('policy-version').text()).toBe('Version 4');
      expect(findByTestId('policy-updated-at').findComponent(TimeAgoTooltip).props('time')).toBe(
        '2026-08-20T20:00:00.000Z',
      );
    });

    it('re-enables a disabled policy', async () => {
      fetchPolicy.mockResolvedValue({ ...policy, status: 'disabled' });
      updatePolicy.mockResolvedValue(policy);
      await createComponent();

      await requestToggle();

      expect(updatePolicy).toHaveBeenCalledWith({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: '1',
        policyId: '7',
        params: { lifecycle_state: 'active' },
      });
      expect(findByTestId('policy-status').text()).toBe('Active');
    });

    it('marks the button busy while the request is in flight', async () => {
      updatePolicy.mockReturnValue(new Promise(() => {}));
      await createComponent();

      await requestToggle();

      expect(findToggleButton().props('loading')).toBe(true);
    });

    it('keeps the status and alerts generically when the update fails', async () => {
      const error = new Error('API is down');
      updatePolicy.mockRejectedValue(error);
      await createComponent();

      await requestToggle();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'The policy could not be updated. Try again.',
      });
      expect(findByTestId('policy-status').text()).toBe('Active');
      expect(findToggleButton().props('loading')).toBe(false);
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    it("surfaces the store's message when the update is rejected as invalid", async () => {
      updatePolicy.mockRejectedValue(new PolicyStoreMutationError('Lifecycle state is invalid'));
      await createComponent();

      await requestToggle();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Lifecycle state is invalid' });
    });

    it('surfaces a top-level GraphQL error message, such as the policy no longer existing', async () => {
      const error = Object.assign(new Error('GraphQL error'), {
        graphQLErrors: [
          {
            message:
              "The resource that you are attempting to access does not exist or you don't have permission to perform this action",
          },
        ],
      });
      updatePolicy.mockRejectedValue(error);
      await createComponent();

      await requestToggle();

      expect(createAlert).toHaveBeenCalledWith({
        message:
          "The resource that you are attempting to access does not exist or you don't have permission to perform this action",
      });
      expect(findByTestId('policy-status').text()).toBe('Active');
    });
  });

  describe('deleting the policy', () => {
    const requestDelete = async () => {
      findDeleteButton().vm.$emit('click');
      await waitForPromises();
    };

    it('asks for confirmation naming the policy', async () => {
      await createComponent();

      await requestDelete();

      expect(confirmAction).toHaveBeenCalledWith(
        'Are you sure you want to delete Production gate? This action cannot be undone.',
        expect.objectContaining({ primaryBtnVariant: 'danger' }),
      );
    });

    it('deletes the policy through deletePolicy and returns to the list', async () => {
      await createComponent();

      await requestDelete();

      expect(deletePolicy).toHaveBeenCalledWith({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: '1',
        policyId: '7',
      });
      expect(visitUrl).toHaveBeenCalledWith('/-/security/policy_store');
    });

    it('does not delete when the confirmation is declined', async () => {
      confirmAction.mockResolvedValue(false);
      await createComponent();

      await requestDelete();

      expect(deletePolicy).not.toHaveBeenCalled();
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
    });

    it('ignores further clicks while the confirmation is pending', async () => {
      confirmAction.mockReturnValue(new Promise(() => {}));
      await createComponent();

      findDeleteButton().vm.$emit('click');
      findDeleteButton().vm.$emit('click');
      await waitForPromises();

      expect(confirmAction).toHaveBeenCalledTimes(1);
      expect(findDeleteButton().props('loading')).toBe(true);
    });

    it('resets the busy state after deleting when there is no list path to return to', async () => {
      await createComponent({ listPath: '' });

      await requestDelete();

      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
    });

    it('marks the delete button busy while the request is in flight', async () => {
      deletePolicy.mockReturnValue(new Promise(() => {}));
      await createComponent();

      await requestDelete();

      expect(findDeleteButton().props('loading')).toBe(true);
    });

    it('stays on the page and alerts when the delete fails', async () => {
      deletePolicy.mockRejectedValue(new Error('API is down'));
      await createComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'The policy could not be deleted. Try again.',
      });
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
      expect(Sentry.captureException).toHaveBeenCalledWith(
        expect.objectContaining({ message: expect.stringContaining('API is down') }),
      );
    });

    it('surfaces a top-level GraphQL error message when the delete is rejected', async () => {
      const error = Object.assign(new Error('GraphQL error'), {
        graphQLErrors: [
          {
            message:
              "The resource that you are attempting to access does not exist or you don't have permission to perform this action",
          },
        ],
      });
      deletePolicy.mockRejectedValue(error);
      await createComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({
        message:
          "The resource that you are attempting to access does not exist or you don't have permission to perform this action",
      });
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
    });

    it('alerts with the store message when the store rejects the delete', async () => {
      deletePolicy.mockRejectedValue(new PolicyStoreMutationError('Policy could not be deleted'));
      await createComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Policy could not be deleted' });
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findDeleteButton().props('loading')).toBe(false);
    });

    it('joins multiple store messages so none is silently dropped', async () => {
      deletePolicy.mockRejectedValue(
        new PolicyStoreMutationError('Policy is stale, Policy is locked'),
      );
      await createComponent();

      await requestDelete();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Policy is stale, Policy is locked' });
    });
  });

  describe('when in group context', () => {
    const createGroupComponent = (provide = {}) =>
      createComponent({
        namespaceType: 'group',
        namespacePath: 'my-org/my-group',
        ...provide,
      });

    const findToggleButton = () => wrapper.findComponent('[data-testid="toggle-status-button"]');
    const findGroupDeleteButton = () =>
      wrapper.findComponent('[data-testid="delete-policy-button"]');

    const requestGroupToggle = async () => {
      findToggleButton().vm.$emit('click');
      await waitForPromises();
    };

    const requestGroupDelete = async () => {
      findGroupDeleteButton().vm.$emit('click');
      await waitForPromises();
    };

    it('fetches the policy using group context', async () => {
      await createGroupComponent();

      expect(fetchPolicy).toHaveBeenCalledWith(NAMESPACE_TYPE_GROUP, 'my-org/my-group', '7');
    });

    it('toggles status using group context', async () => {
      await createGroupComponent();

      await requestGroupToggle();

      expect(updatePolicy).toHaveBeenCalledWith({
        namespaceType: NAMESPACE_TYPE_GROUP,
        namespaceIdentifier: 'my-org/my-group',
        policyId: '7',
        params: { lifecycle_state: 'disabled' },
      });
    });

    describe('deleting the policy', () => {
      it('deletes through deletePolicy with group context', async () => {
        await createGroupComponent({ listPath: '/-/security/policy_store' });

        await requestGroupDelete();

        expect(deletePolicy).toHaveBeenCalledWith({
          namespaceType: NAMESPACE_TYPE_GROUP,
          namespaceIdentifier: 'my-org/my-group',
          policyId: '7',
        });
        expect(visitUrl).toHaveBeenCalledWith('/-/security/policy_store');
      });

      it('shows an error when the delete fails', async () => {
        const error = new Error('forbidden');
        error.response = { data: { message: 'Policy is locked' } };
        deletePolicy.mockRejectedValue(error);
        await createGroupComponent();

        await requestGroupDelete();

        expect(createAlert).toHaveBeenCalledWith({ message: 'Policy is locked' });
        expect(findGroupDeleteButton().props('loading')).toBe(false);
      });
    });
  });
});
