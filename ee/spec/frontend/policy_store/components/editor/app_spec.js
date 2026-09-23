import { shallowMount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { visitUrl, visitUrlWithAlerts } from '~/lib/utils/url_utility';
import App from 'ee/policy_store/components/editor/app.vue';
import StepWizard from 'ee/policy_store/components/editor/step_wizard.vue';
import { createAlert } from '~/alert';
import {
  fetchPolicy,
  createPolicy,
  updatePolicy,
  NAMESPACE_TYPE_GROUP,
  NAMESPACE_TYPE_ORGANIZATION,
} from 'ee/policy_store/policies';
import { PolicyStoreMutationError } from 'ee/policy_store/utils';
import { mockWizardState, mockPolicyParams } from '../../mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/alert');
jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  visitUrl: jest.fn(),
  visitUrlWithAlerts: jest.fn(),
}));
jest.mock('ee/policy_store/policies', () => ({
  fetchPolicy: jest.fn(),
  createPolicy: jest.fn(),
  updatePolicy: jest.fn(),
  NAMESPACE_TYPE_GROUP: 'group',
  NAMESPACE_TYPE_ORGANIZATION: 'organization',
}));

describe('PolicyStoreEditorRoot', () => {
  let wrapper;

  const policy = { id: 2, name: 'Merge gate', trigger_type: 'merge_request', status: 'active' };

  const findWizard = () => wrapper.findComponent(StepWizard);

  // Returns the settle promise so most tests `await createComponent()`; the
  // loading test skips the await to observe the in-flight state.
  const createComponent = (provide = {}) => {
    wrapper = shallowMount(App, {
      provide: { organizationId: '1', namespaceType: 'organization', ...provide },
    });

    return waitForPromises();
  };

  beforeEach(() => {
    fetchPolicy.mockResolvedValue(policy);
    createPolicy.mockResolvedValue(policy);
    updatePolicy.mockResolvedValue(policy);
  });

  it('resolves the edited policy through the single-policy endpoint', async () => {
    await createComponent({ policyId: '2' });

    expect(fetchPolicy).toHaveBeenCalledWith(NAMESPACE_TYPE_ORGANIZATION, '1', '2');
    expect(findWizard().props('policy')).toEqual(policy);
  });

  // The wizard reads its policy prop once, on mount, so it must not mount
  // until the fetch settles.
  it('shows a loading icon instead of the wizard while the policy loads', () => {
    fetchPolicy.mockReturnValue(new Promise(() => {}));

    createComponent({ policyId: '2' });

    expect(wrapper.find('[data-testid="policy-loading"]').exists()).toBe(true);
    expect(findWizard().exists()).toBe(false);
  });

  it('shows an error instead of a blank editor when the policy fails to load', async () => {
    const error = new Error('not found');
    fetchPolicy.mockRejectedValue(error);

    await createComponent({ policyId: '2' });

    expect(wrapper.find('[data-testid="policy-error"]').text()).toContain(
      'The policy could not be loaded from the Policy Store API.',
    );
    expect(findWizard().exists()).toBe(false);
    expect(Sentry.captureException).toHaveBeenCalledWith(error);
  });

  it('does not fetch and renders a blank wizard when there is no policy id', async () => {
    await createComponent();

    expect(fetchPolicy).not.toHaveBeenCalled();
    expect(findWizard().props('policy')).toBe(null);
  });

  it('returns to the list when a new policy is cancelled', async () => {
    await createComponent({ listPath: '/-/security/policy_store' });

    findWizard().vm.$emit('cancel');

    expect(visitUrl).toHaveBeenCalledWith('/-/security/policy_store');
  });

  it('returns to the detail view when an edit is cancelled', async () => {
    await createComponent({ policyId: '2', listPath: '/-/security/policy_store' });

    findWizard().vm.$emit('cancel');

    expect(visitUrl).toHaveBeenCalledWith('/-/security/policy_store/2');
  });

  describe('saving the policy', () => {
    const requestSave = async () => {
      findWizard().vm.$emit('save', mockWizardState);
      await waitForPromises();
    };

    it('creates a new policy and returns to the list with a success confirmation', async () => {
      await createComponent({ listPath: '/-/security/policy_store' });

      await requestSave();

      expect(createPolicy).toHaveBeenCalledWith(NAMESPACE_TYPE_ORGANIZATION, '1', mockPolicyParams);
      expect(updatePolicy).not.toHaveBeenCalled();
      expect(visitUrlWithAlerts).toHaveBeenCalledWith('/-/security/policy_store', [
        {
          id: 'policy-store-policy-created',
          message: 'Policy Prod gate was created.',
          variant: 'success',
        },
      ]);
    });

    it('updates the edited policy and returns to its detail view with a success confirmation', async () => {
      await createComponent({ policyId: '2', listPath: '/-/security/policy_store' });

      await requestSave();

      expect(updatePolicy).toHaveBeenCalledWith({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: '1',
        policyId: '2',
        params: mockPolicyParams,
      });
      expect(createPolicy).not.toHaveBeenCalled();
      expect(visitUrlWithAlerts).toHaveBeenCalledWith('/-/security/policy_store/2', [
        {
          id: 'policy-store-policy-updated',
          message: 'Policy Prod gate was updated.',
          variant: 'success',
        },
      ]);
    });

    it('does not overwrite the stored scope when the Scope step was not touched', async () => {
      await createComponent({ policyId: '2' });

      findWizard().vm.$emit('save', { ...mockWizardState, scopeChanged: false });
      await waitForPromises();

      const { policy_scope: policyScope, ...paramsWithoutScope } = mockPolicyParams;
      expect(updatePolicy).toHaveBeenCalledWith({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: '1',
        policyId: '2',
        params: paramsWithoutScope,
      });
    });

    it('sends an untouched scope on create, where there is nothing to overwrite', async () => {
      await createComponent();

      findWizard().vm.$emit('save', { ...mockWizardState, scopeChanged: false });
      await waitForPromises();

      expect(createPolicy).toHaveBeenCalledWith(NAMESPACE_TYPE_ORGANIZATION, '1', mockPolicyParams);
    });

    it('marks the wizard as saving while the request is in flight', async () => {
      createPolicy.mockReturnValue(new Promise(() => {}));
      await createComponent();

      await requestSave();

      expect(findWizard().props('saving')).toBe(true);
    });

    it('stays on the editor and alerts generically when the save fails', async () => {
      const error = new Error('API is down');
      createPolicy.mockRejectedValue(error);
      await createComponent();

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'The policy could not be saved. Try again.',
      });
      expect(visitUrl).not.toHaveBeenCalled();
      expect(findWizard().props('saving')).toBe(false);
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    it("surfaces the store's validation message when the mutation rejects the save", async () => {
      createPolicy.mockRejectedValue(
        new PolicyStoreMutationError('rule 0: unsupported rule type "calendar"'),
      );
      await createComponent();

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'rule 0: unsupported rule type "calendar"',
      });
    });

    it("surfaces the store's validation message when the mutation rejects an update", async () => {
      updatePolicy.mockRejectedValue(new PolicyStoreMutationError('Rules is invalid'));
      await createComponent({ policyId: '2' });

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Rules is invalid' });
    });

    it('surfaces a top-level GraphQL error message when the update is refused', async () => {
      const error = Object.assign(new Error('GraphQL error'), {
        graphQLErrors: [{ message: 'Could not complete the policy store request' }],
      });
      updatePolicy.mockRejectedValue(error);
      await createComponent({ policyId: '2' });

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Could not complete the policy store request',
      });
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    describe('when the save is rejected because a rule does not parse', () => {
      const refusal = 'rules[0] is invalid: expecting expression (at 5:1)';

      beforeEach(async () => {
        createPolicy.mockRejectedValue(new PolicyStoreMutationError(refusal));
        await createComponent();

        await requestSave();
      });

      it('surfaces the refusal and leaves the author on the editor', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: refusal });
        expect(visitUrl).not.toHaveBeenCalled();
        expect(findWizard().props('saving')).toBe(false);
      });

      it('does not report the rejection to Sentry, since it is author input', () => {
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });
    });

    it('leaves a parse refusal unreported on the edit page too', async () => {
      updatePolicy.mockRejectedValue(
        new PolicyStoreMutationError('rules[0] is invalid: unexpected token; missing value'),
      );
      await createComponent({ policyId: '2' });

      await requestSave();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'rules[0] is invalid: unexpected token; missing value',
      });
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    it('reports a merged-program refusal, which this pattern does not cover', async () => {
      const error = new PolicyStoreMutationError(
        'policy_rego is invalid: var msg is unsafe (at 3:3)',
      );
      createPolicy.mockRejectedValue(error);
      await createComponent();

      await requestSave();

      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    describe('when the save is rejected because the name is taken', () => {
      beforeEach(async () => {
        createPolicy.mockRejectedValue(new PolicyStoreMutationError('Name has already been taken'));
        await createComponent();

        await requestSave();
      });

      it('puts the rejection on the name field instead of a page alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
        expect(findWizard().props('nameError')).toBe(
          'A policy with this name already exists. Choose a different name.',
        );
        expect(findWizard().props('saving')).toBe(false);
      });

      it('does not report the rejection to Sentry, since it is ordinary user input', () => {
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });

      it('clears the name error once the name is not a duplicate', async () => {
        await findWizard().vm.$emit('name-update');

        expect(findWizard().props('nameError')).toBe('');
      });

      it('clears the name error as soon as another save attempt starts', async () => {
        createPolicy.mockReturnValue(new Promise(() => {}));

        await requestSave();

        expect(findWizard().props('nameError')).toBe('');
      });
    });

    it('routes a duplicate-name rejection to the name field on the edit page too', async () => {
      updatePolicy.mockRejectedValue(new PolicyStoreMutationError('Name has already been taken'));
      await createComponent({ policyId: '2' });

      await requestSave();

      expect(createAlert).not.toHaveBeenCalled();
      expect(findWizard().props('nameError')).toBe(
        'A policy with this name already exists. Choose a different name.',
      );
    });
  });

  describe('when in group context', () => {
    const createGroupComponent = (provide = {}) =>
      createComponent({
        namespaceType: 'group',
        namespacePath: 'my-org/my-group',
        ...provide,
      });

    it('fetches the policy using group context', async () => {
      await createGroupComponent({ policyId: '2' });

      expect(fetchPolicy).toHaveBeenCalledWith(NAMESPACE_TYPE_GROUP, 'my-org/my-group', '2');
    });

    it('creates a new policy using group context', async () => {
      await createGroupComponent({ listPath: '/-/security/policy_store' });

      findWizard().vm.$emit('save', mockWizardState);
      await waitForPromises();

      expect(createPolicy).toHaveBeenCalledWith(
        NAMESPACE_TYPE_GROUP,
        'my-org/my-group',
        mockPolicyParams,
      );
    });

    it('updates a policy using group context', async () => {
      await createGroupComponent({ policyId: '2', listPath: '/-/security/policy_store' });

      findWizard().vm.$emit('save', mockWizardState);
      await waitForPromises();

      expect(updatePolicy).toHaveBeenCalledWith({
        namespaceType: NAMESPACE_TYPE_GROUP,
        namespaceIdentifier: 'my-org/my-group',
        policyId: '2',
        params: mockPolicyParams,
      });
    });
  });
});
