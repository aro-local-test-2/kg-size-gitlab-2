import {
  fetchPolicy,
  createPolicy,
  updatePolicy,
  deletePolicy,
  NAMESPACE_TYPE_GROUP,
  NAMESPACE_TYPE_ORGANIZATION,
} from 'ee/policy_store/policies';
import Api from 'ee/api';
import { gqlClient } from 'ee/policy_store/apollo';
import getPolicyStorePolicies from 'ee/policy_store/graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStorePolicies from 'ee/policy_store/graphql/get_group_policy_store_policies.query.graphql';
import getGroupPolicyStoreCatalogs from 'ee/policy_store/graphql/get_group_policy_store_catalogs.query.graphql';
import governPolicyCreateMutation from 'ee/policy_store/graphql/govern_policy_create.mutation.graphql';
import governPolicyUpdateMutation from 'ee/policy_store/graphql/govern_policy_update.mutation.graphql';
import governPolicyDeleteMutation from 'ee/policy_store/graphql/govern_policy_delete.mutation.graphql';
import { PolicyStoreMutationError } from 'ee/policy_store/utils';

jest.mock('ee/api');

jest.mock('ee/policy_store/apollo', () => {
  const query = jest.fn();
  const mutate = jest.fn();
  return { __esModule: true, default: jest.fn(), gqlClient: () => ({ query, mutate }) };
});

// A policy as the policies query and the update mutation return it.
const graphqlPolicy = {
  __typename: 'GovernPolicy',
  id: 7,
  organizationId: 1,
  namespaceId: null,
  name: 'Production gate',
  description: 'Gates production deployments',
  version: 1,
  triggerType: 'deployment_requested',
  rules: [{ type: 'custom', value: 'package governance' }],
  policyRego: 'package governance\n',
  actions: [{ type: 'block' }],
  policyScope: { projects: { including: [1, 2, 3] } },
  scopeRego: 'package gitlab.scope\n',
  scopeDimensions: null,
  mode: 'enforce',
  lifecycleState: 'active',
  createdAt: '2026-08-10T10:00:00+00:00',
  updatedAt: '2026-08-11T10:00:00+00:00',
};

const triggersResponse = {
  data: {
    organization: {
      id: 'gid://gitlab/Organizations::Organization/1',
      policyStore: {
        triggers: [
          { id: 'deployment_requested', name: 'Deployment requested' },
          { id: 'merge_requested', name: 'Merge Request' },
        ],
      },
    },
  },
};

const groupTriggersResponse = {
  data: {
    group: {
      id: 'gid://gitlab/Group/42',
      policyStore: {
        triggers: [
          { id: 'deployment_requested', name: 'Deployment requested' },
          { id: 'merge_requested', name: 'Merge Request' },
        ],
      },
    },
  },
};

// A policy as the REST API returns it (snake_case).
const apiPolicy = {
  id: 7,
  organization_id: 1,
  namespace_id: 42,
  name: 'Production gate',
  description: 'Gates production deployments',
  version: 1,
  trigger_type: 'deployment_requested',
  rules: [{ type: 'custom', value: 'package governance' }],
  policy_rego: 'package governance\n',
  actions: [{ type: 'block' }],
  policy_scope: { projects: { including: [1, 2, 3] } },
  scope_rego: 'package gitlab.scope\n',
  scope_dimensions: null,
  mode: 'enforce',
  lifecycle_state: 'active',
  created_at: '2026-08-10T10:00:00+00:00',
  updated_at: '2026-08-11T10:00:00+00:00',
};

describe('policy store policies', () => {
  beforeEach(() => {
    gqlClient().query.mockResolvedValue(triggersResponse);
  });

  describe('fetchPolicy', () => {
    const policiesResponse = (policies) => ({
      data: {
        organization: {
          id: 'gid://gitlab/Organizations::Organization/1',
          policyStore: { policies },
        },
      },
    });

    // Both the policies query and the degradable triggers query go through the
    // same client, so the mock dispatches on the query document like Apollo does.
    const mockPolicyQuery = ({ policies = [graphqlPolicy], triggersFail = false } = {}) => {
      gqlClient().query.mockImplementation(({ query }) => {
        if (query === getPolicyStorePolicies) {
          return Promise.resolve(policiesResponse(policies));
        }

        return triggersFail
          ? Promise.reject(new Error('query failed'))
          : Promise.resolve(triggersResponse);
      });
    };

    it('fetches the policy through the policies query and maps it like the list', async () => {
      mockPolicyQuery();

      const policy = await fetchPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, '7');

      expect(gqlClient().query).toHaveBeenCalledWith(
        expect.objectContaining({
          query: getPolicyStorePolicies,
          variables: { id: 'gid://gitlab/Organizations::Organization/1', ids: [7] },
          fetchPolicy: 'network-only',
        }),
      );
      expect(policy).toMatchObject({
        id: 7,
        name: 'Production gate',
        type: 'Deployment requested',
        trigger_type: 'deployment_requested',
        status: 'active',
        scopedProjectsCount: 3,
        policy_rego: 'package governance\n',
        scope_rego: 'package gitlab.scope\n',
        created_at: '2026-08-10T10:00:00+00:00',
        updated_at: '2026-08-11T10:00:00+00:00',
      });
      expect(policy).not.toHaveProperty('__typename');
    });

    it('keeps the stored shape of the free-form JSON fields', async () => {
      mockPolicyQuery();

      const policy = await fetchPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, 7);

      expect(policy.rules).toEqual([{ type: 'custom', value: 'package governance' }]);
      expect(policy.policy_scope).toEqual({ projects: { including: [1, 2, 3] } });
    });

    it('rejects when the organization does not have the policy', async () => {
      mockPolicyQuery({ policies: [] });

      await expect(fetchPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, 7)).rejects.toThrow('not found');
    });

    it('rejects when the policies are not readable', async () => {
      mockPolicyQuery({ policies: null });

      await expect(fetchPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, 7)).rejects.toThrow('not found');
    });

    it('rejects when the policy store is not available', async () => {
      gqlClient().query.mockResolvedValue({
        data: {
          organization: { id: 'gid://gitlab/Organizations::Organization/1', policyStore: null },
        },
      });

      await expect(fetchPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, 7)).rejects.toThrow('not found');
    });

    it('rejects with the request error when the query fails', async () => {
      gqlClient().query.mockRejectedValue(new Error('query failed'));

      await expect(fetchPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, 7)).rejects.toThrow('query failed');
    });

    it('still resolves the policy when the triggers query fails', async () => {
      mockPolicyQuery({
        policies: [{ ...graphqlPolicy, triggerType: 'merge_requested' }],
        triggersFail: true,
      });

      const policy = await fetchPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, 7);

      expect(policy.type).toBe('merge_requested');
    });

    describe('when in group context', () => {
      const groupPoliciesResponse = (policies) => ({
        data: {
          group: {
            id: 'gid://gitlab/Group/42',
            policyStore: { policies },
          },
        },
      });

      const mockGroupPolicyQuery = ({ policies = [graphqlPolicy], triggersFail = false } = {}) => {
        gqlClient().query.mockImplementation(({ query }) => {
          if (query === getGroupPolicyStorePolicies) {
            return Promise.resolve(groupPoliciesResponse(policies));
          }
          if (query === getGroupPolicyStoreCatalogs) {
            return triggersFail
              ? Promise.reject(new Error('query failed'))
              : Promise.resolve(groupTriggersResponse);
          }
          return Promise.reject(new Error(`Unexpected query: ${query}`));
        });
      };

      it('fetches the policy through the group policies query', async () => {
        mockGroupPolicyQuery();

        const policy = await fetchPolicy(NAMESPACE_TYPE_GROUP, 'my-org/my-group', '7');

        expect(gqlClient().query).toHaveBeenCalledWith(
          expect.objectContaining({
            query: getGroupPolicyStorePolicies,
            variables: { fullPath: 'my-org/my-group', ids: [7] },
            fetchPolicy: 'network-only',
          }),
        );
        expect(policy).toMatchObject({
          id: 7,
          name: 'Production gate',
          type: 'Deployment requested',
        });
      });

      it('fetches triggers through the group catalogs query', async () => {
        mockGroupPolicyQuery();

        await fetchPolicy(NAMESPACE_TYPE_GROUP, 'my-org/my-group', 7);

        expect(gqlClient().query).toHaveBeenCalledWith(
          expect.objectContaining({
            query: getGroupPolicyStoreCatalogs,
            variables: { fullPath: 'my-org/my-group' },
          }),
        );
      });

      it('rejects when the group does not have the policy', async () => {
        mockGroupPolicyQuery({ policies: [] });

        await expect(fetchPolicy(NAMESPACE_TYPE_GROUP, 'my-org/my-group', 7)).rejects.toThrow(
          'not found',
        );
      });
    });
  });

  describe('createPolicy', () => {
    const params = {
      name: 'Production gate',
      description: 'Gates production deployments',
      mode: 'enforce',
      policy_scope: { projects: { including: [3] } },
      trigger_type: 'deployment_requested',
      rules: [{ type: 'custom', value: 'package governance' }],
      actions: [],
    };

    const mutationResponse = ({
      policy = { __typename: 'GovernPolicy', id: 7 },
      errors = [],
    } = {}) => ({
      data: { governPolicyCreate: { policy, errors } },
    });

    it('creates the policy through the mutation, adapting the params to its arguments', async () => {
      gqlClient().mutate.mockResolvedValue(mutationResponse());

      const policy = await createPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, params);

      expect(gqlClient().mutate).toHaveBeenCalledWith({
        mutation: governPolicyCreateMutation,
        variables: {
          organizationId: 'gid://gitlab/Organizations::Organization/1',
          name: 'Production gate',
          description: 'Gates production deployments',
          mode: 'enforce',
          triggerType: 'deployment_requested',
          policyScope: { projects: { including: [3] } },
          rules: [{ type: 'custom', value: 'package governance' }],
          actions: [],
        },
      });
      expect(policy).toMatchObject({ id: 7 });
    });

    it("sends the caller's organizationId even when the params carry one", async () => {
      gqlClient().mutate.mockResolvedValue(mutationResponse());

      await createPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, {
        ...params,
        organizationId: 'gid://gitlab/Organizations::Organization/999',
      });

      expect(gqlClient().mutate).toHaveBeenCalledWith({
        mutation: governPolicyCreateMutation,
        variables: expect.objectContaining({
          organizationId: 'gid://gitlab/Organizations::Organization/1',
        }),
      });
    });

    // lifecycleState is spelled the way the update document declares it, so
    // only a check against the create document itself can catch it here.
    it('rejects a param only the update mutation declares', async () => {
      await expect(
        createPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, { ...params, lifecycle_state: 'disabled' }),
      ).rejects.toThrow('Policy store param not declared by the mutation: lifecycle_state');
      expect(gqlClient().mutate).not.toHaveBeenCalled();
    });

    it('rejects with the bare store message when the params fail validation', async () => {
      gqlClient().mutate.mockResolvedValue(
        mutationResponse({ policy: null, errors: ['Name has already been taken'] }),
      );

      const promise = createPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, params);

      await expect(promise).rejects.toThrow(PolicyStoreMutationError);
      await expect(promise).rejects.toThrow('Name has already been taken');
    });

    it('joins multiple store messages so none is silently dropped', async () => {
      gqlClient().mutate.mockResolvedValue(
        mutationResponse({ policy: null, errors: ['Name is too long', 'Rules is invalid'] }),
      );

      await expect(createPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, params)).rejects.toThrow(
        'Name is too long, Rules is invalid',
      );
    });

    it('rejects with the request error when the mutation fails', async () => {
      gqlClient().mutate.mockRejectedValue(new Error('network down'));

      await expect(createPolicy(NAMESPACE_TYPE_ORGANIZATION, 1, params)).rejects.toThrow(
        'network down',
      );
    });

    describe('when in group context', () => {
      it('creates the policy through REST instead of GraphQL', async () => {
        Api.createGroupPolicyStorePolicy.mockResolvedValue({
          data: { id: 7, name: 'Production gate' },
        });

        const policy = await createPolicy(NAMESPACE_TYPE_GROUP, 'my-org/my-group', params);

        expect(gqlClient().mutate).not.toHaveBeenCalled();
        expect(Api.createGroupPolicyStorePolicy).toHaveBeenCalledWith('my-org/my-group', params);
        expect(policy).toMatchObject({ id: 7, name: 'Production gate' });
      });

      it('rejects with the request error when the REST call fails', async () => {
        Api.createGroupPolicyStorePolicy.mockRejectedValue(new Error('forbidden'));

        await expect(createPolicy(NAMESPACE_TYPE_GROUP, 'my-org/my-group', params)).rejects.toThrow(
          'forbidden',
        );
      });
    });
  });

  describe('updatePolicy', () => {
    // Everything the editor sends when the Scope step was touched.
    const params = {
      name: 'Renamed gate',
      description: 'Gates production deployments',
      mode: 'enforce',
      policy_scope: { projects: { including: [3] } },
      trigger_type: 'deployment_requested',
      rules: [{ type: 'custom', value: 'package governance' }],
      actions: [],
    };

    const mutationResponse = ({ policy = graphqlPolicy, errors = [] } = {}) => ({
      data: { governPolicyUpdate: { policy, errors } },
    });

    const sentVariables = () => gqlClient().mutate.mock.calls[0][0].variables;

    beforeEach(() => {
      gqlClient().mutate.mockResolvedValue(
        mutationResponse({ policy: { ...graphqlPolicy, name: 'Renamed gate', version: 2 } }),
      );
    });

    it('updates the policy through the mutation, adapting the params to its arguments', async () => {
      await updatePolicy({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: 1,
        policyId: '7',
        params,
      });

      expect(gqlClient().mutate).toHaveBeenCalledWith({
        mutation: governPolicyUpdateMutation,
        variables: {
          organizationId: 'gid://gitlab/Organizations::Organization/1',
          policyId: 7,
          name: 'Renamed gate',
          description: 'Gates production deployments',
          mode: 'enforce',
          triggerType: 'deployment_requested',
          policyScope: { projects: { including: [3] } },
          rules: [{ type: 'custom', value: 'package governance' }],
          actions: [],
        },
      });
    });

    // Pinned in full: the detail page replaces its policy with this result, so
    // a field dropped from the shared fragment must fail here, not on screen.
    it('maps the updated policy like the list', async () => {
      const policy = await updatePolicy({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: 1,
        policyId: 7,
        params,
      });

      expect(policy).toEqual({
        id: 7,
        organization_id: 1,
        namespace_id: null,
        name: 'Renamed gate',
        description: 'Gates production deployments',
        version: 2,
        trigger_type: 'deployment_requested',
        rules: [{ type: 'custom', value: 'package governance' }],
        policy_rego: 'package governance\n',
        actions: [{ type: 'block' }],
        policy_scope: { projects: { including: [1, 2, 3] } },
        scope_rego: 'package gitlab.scope\n',
        scope_dimensions: null,
        mode: 'enforce',
        lifecycle_state: 'active',
        created_at: '2026-08-10T10:00:00+00:00',
        updated_at: '2026-08-11T10:00:00+00:00',
        type: 'Deployment requested',
        status: 'active',
        scopedProjectsCount: 3,
      });
    });

    // The mutation clears a field on an explicit null and keeps it when the
    // argument is omitted, so an untouched scope must not be sent at all.
    it('leaves out the arguments for params that were not supplied', async () => {
      const { policy_scope: policyScope, ...paramsWithoutScope } = params;

      await updatePolicy({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: 1,
        policyId: 7,
        params: paramsWithoutScope,
      });

      expect(sentVariables()).not.toHaveProperty('policyScope');
      expect(sentVariables()).toMatchObject({ name: 'Renamed gate', policyId: 7 });
    });

    it("sends only the lifecycle state for the detail page's status toggle", async () => {
      await updatePolicy({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: 1,
        policyId: 7,
        params: { lifecycle_state: 'disabled' },
      });

      expect(sentVariables()).toEqual({
        organizationId: 'gid://gitlab/Organizations::Organization/1',
        policyId: 7,
        lifecycleState: 'disabled',
      });
    });

    // The server ignores undeclared variables, so an unmapped snake_case
    // param would otherwise be dropped without any error.
    it('rejects a param the mutation document does not declare', async () => {
      await expect(
        updatePolicy({
          namespaceType: NAMESPACE_TYPE_ORGANIZATION,
          namespaceIdentifier: 1,
          policyId: 7,
          params: { scope_rego: 'package scope' },
        }),
      ).rejects.toThrow('Policy store param not declared by the mutation: scope_rego');
      expect(gqlClient().mutate).not.toHaveBeenCalled();
    });

    it('rejects with the bare store message when the params fail validation', async () => {
      gqlClient().mutate.mockResolvedValue(
        mutationResponse({ policy: null, errors: ['Lifecycle state is invalid'] }),
      );

      const promise = updatePolicy({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: 1,
        policyId: 7,
        params: { lifecycle_state: 'paused' },
      });

      await expect(promise).rejects.toThrow(PolicyStoreMutationError);
      await expect(promise).rejects.toThrow('Lifecycle state is invalid');
    });

    it('joins multiple store messages so none is silently dropped', async () => {
      gqlClient().mutate.mockResolvedValue(
        mutationResponse({ policy: null, errors: ['Name is too long', 'Rules is invalid'] }),
      );

      await expect(
        updatePolicy({
          namespaceType: NAMESPACE_TYPE_ORGANIZATION,
          namespaceIdentifier: 1,
          policyId: 7,
          params,
        }),
      ).rejects.toThrow('Name is too long, Rules is invalid');
    });

    it('rejects with the request error when the mutation fails', async () => {
      gqlClient().mutate.mockRejectedValue(new Error('network down'));

      await expect(
        updatePolicy({
          namespaceType: NAMESPACE_TYPE_ORGANIZATION,
          namespaceIdentifier: 1,
          policyId: 7,
          params,
        }),
      ).rejects.toThrow('network down');
    });

    it('still resolves the policy when the triggers query fails', async () => {
      gqlClient().mutate.mockResolvedValue(
        mutationResponse({ policy: { ...graphqlPolicy, triggerType: 'merge_requested' } }),
      );
      gqlClient().query.mockRejectedValue(new Error('query failed'));

      const policy = await updatePolicy({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: 1,
        policyId: 7,
        params,
      });

      expect(policy.type).toBe('merge_requested');
    });

    describe('when in group context', () => {
      beforeEach(() => {
        gqlClient().query.mockResolvedValue(groupTriggersResponse);
      });

      it('updates through the group REST endpoint and maps the policy', async () => {
        Api.updateGroupPolicyStorePolicy.mockResolvedValue({
          data: { ...apiPolicy, name: 'Renamed gate' },
        });

        const policy = await updatePolicy({
          namespaceType: NAMESPACE_TYPE_GROUP,
          namespaceIdentifier: 'my-org/my-group',
          policyId: 7,
          params,
        });

        expect(Api.updateGroupPolicyStorePolicy).toHaveBeenCalledWith('my-org/my-group', 7, params);
        expect(policy).toMatchObject({ id: 7, name: 'Renamed gate', type: 'Deployment requested' });
      });

      it('fetches triggers through the group catalogs query', async () => {
        Api.updateGroupPolicyStorePolicy.mockResolvedValue({ data: apiPolicy });

        await updatePolicy({
          namespaceType: NAMESPACE_TYPE_GROUP,
          namespaceIdentifier: 'my-org/my-group',
          policyId: 7,
          params,
        });

        expect(gqlClient().query).toHaveBeenCalledWith(
          expect.objectContaining({
            query: getGroupPolicyStoreCatalogs,
            variables: { fullPath: 'my-org/my-group' },
          }),
        );
      });

      it('rejects with the request error when the group API fails', async () => {
        Api.updateGroupPolicyStorePolicy.mockRejectedValue(new Error('forbidden'));

        await expect(
          updatePolicy({
            namespaceType: NAMESPACE_TYPE_GROUP,
            namespaceIdentifier: 'my-org/my-group',
            policyId: 7,
            params,
          }),
        ).rejects.toThrow('forbidden');
      });
    });
  });

  describe('deletePolicy', () => {
    const mutationResponse = ({ errors = [] } = {}) => ({
      data: { governPolicyDelete: { errors } },
    });

    beforeEach(() => {
      gqlClient().mutate.mockResolvedValue(mutationResponse());
    });

    it('deletes the policy through the mutation for organizations', async () => {
      await deletePolicy({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: 1,
        policyId: '7',
      });

      expect(gqlClient().mutate).toHaveBeenCalledWith({
        mutation: governPolicyDeleteMutation,
        variables: {
          organizationId: 'gid://gitlab/Organizations::Organization/1',
          id: 7,
        },
      });
    });

    it('converts string policyId to number for the mutation', async () => {
      await deletePolicy({
        namespaceType: NAMESPACE_TYPE_ORGANIZATION,
        namespaceIdentifier: 1,
        policyId: '42',
      });

      expect(gqlClient().mutate).toHaveBeenCalledWith(
        expect.objectContaining({ variables: expect.objectContaining({ id: 42 }) }),
      );
    });

    it('rejects with the store message when the delete fails validation', async () => {
      gqlClient().mutate.mockResolvedValue(
        mutationResponse({ errors: ['Policy is currently active'] }),
      );

      await expect(
        deletePolicy({
          namespaceType: NAMESPACE_TYPE_ORGANIZATION,
          namespaceIdentifier: 1,
          policyId: 7,
        }),
      ).rejects.toThrow(PolicyStoreMutationError);
      await expect(
        deletePolicy({
          namespaceType: NAMESPACE_TYPE_ORGANIZATION,
          namespaceIdentifier: 1,
          policyId: 7,
        }),
      ).rejects.toThrow('Policy is currently active');
    });

    it('rejects with the request error when the mutation fails', async () => {
      gqlClient().mutate.mockRejectedValue(new Error('network down'));

      await expect(
        deletePolicy({
          namespaceType: NAMESPACE_TYPE_ORGANIZATION,
          namespaceIdentifier: 1,
          policyId: 7,
        }),
      ).rejects.toThrow('network down');
    });

    describe('when in group context', () => {
      it('deletes through the group REST endpoint', async () => {
        Api.deleteGroupPolicyStorePolicy.mockResolvedValue({});

        await deletePolicy({
          namespaceType: NAMESPACE_TYPE_GROUP,
          namespaceIdentifier: 'my-org/my-group',
          policyId: 7,
        });

        expect(gqlClient().mutate).not.toHaveBeenCalled();
        expect(Api.deleteGroupPolicyStorePolicy).toHaveBeenCalledWith('my-org/my-group', 7);
      });

      it('rejects with the request error when the REST call fails', async () => {
        Api.deleteGroupPolicyStorePolicy.mockRejectedValue(new Error('forbidden'));

        await expect(
          deletePolicy({
            namespaceType: NAMESPACE_TYPE_GROUP,
            namespaceIdentifier: 'my-org/my-group',
            policyId: 7,
          }),
        ).rejects.toThrow('forbidden');
      });
    });
  });
});
