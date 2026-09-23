import Api from 'ee/api';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPE_ORGANIZATION } from '~/graphql_shared/constants';
import { convertObjectPropsToSnakeCase } from '~/lib/utils/common_utils';
import { gqlClient } from './apollo';
import getPolicyStoreCatalogs from './graphql/get_policy_store_catalogs.query.graphql';
import getPolicyStorePolicies from './graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStoreCatalogs from './graphql/get_group_policy_store_catalogs.query.graphql';
import getGroupPolicyStorePolicies from './graphql/get_group_policy_store_policies.query.graphql';
import governPolicyCreateMutation from './graphql/govern_policy_create.mutation.graphql';
import governPolicyUpdateMutation from './graphql/govern_policy_update.mutation.graphql';
import governPolicyDeleteMutation from './graphql/govern_policy_delete.mutation.graphql';
import { presentable, PolicyStoreMutationError } from './utils';
import { TRIGGERS } from './catalog/triggers';
import { NAMESPACE_TYPE_GROUP, NAMESPACE_TYPE_ORGANIZATION } from './constants';

export { NAMESPACE_TYPE_GROUP, NAMESPACE_TYPE_ORGANIZATION };

// Same resolution the wizard uses: the local catalog supplies the label for ids
// it knows, the API-provided name covers newer triggers, the raw id is the last
// resort. Keeps the list and the editor rendering the same trigger the same way.
const triggerLabel = (triggerType, remoteTriggers) =>
  presentable(remoteTriggers.find(({ id }) => id === triggerType) ?? { id: triggerType }, TRIGGERS)
    .label;

// A stored criterion is a plain array of ids or `{ id }` hashes.
const scopedProjectsCount = (policyScope) => {
  const including = policyScope?.projects?.including;

  return Array.isArray(including) ? including.length : 0;
};

// The list renders `type`, `status` and `scopedProjectsCount` columns on top
// of the policy as the API returns it; the editor reads the raw fields back
// through deserializePolicyData and deserializeScope.
const toListPolicy = (policy, remoteTriggers) => ({
  ...policy,
  type: triggerLabel(policy.trigger_type, remoteTriggers),
  status: policy.lifecycle_state,
  scopedProjectsCount: scopedProjectsCount(policy.policy_scope),
});

/**
 * Maps the `organization.policyStore` GraphQL payload to the rows the list
 * renders — the same derived columns as toListPolicy, but from the camelCase
 * GraphQL fields. trigger_type, rules and actions keep the snake_case shape
 * the REST wrapper produced, because config_info.vue deserializes them from
 * the row.
 *
 * @param {Object|null} policyStore - The `organization.policyStore` query
 *   result; null when the experiment is not active for the organization.
 * @returns {Array} The list rows.
 */
export const toListPolicies = (policyStore) => {
  const triggers = (policyStore?.triggers ?? []).filter((trigger) => trigger?.id);

  return (policyStore?.policies ?? []).map((policy) => ({
    id: policy.id,
    name: policy.name,
    mode: policy.mode,
    trigger_type: policy.triggerType,
    rules: policy.rules,
    actions: policy.actions,
    updated_at: policy.updatedAt,
    type: triggerLabel(policy.triggerType, triggers),
    status: policy.lifecycleState,
    scopedProjectsCount: scopedProjectsCount(policy.policyScope),
  }));
};

// The triggers catalog only affects labels, so its failure degrades them
// instead of failing the policy fetch.
const fetchRemoteTriggers = (namespaceType, namespaceIdentifier) => {
  const isGroup = namespaceType === NAMESPACE_TYPE_GROUP;
  const query = isGroup ? getGroupPolicyStoreCatalogs : getPolicyStoreCatalogs;
  const variables = isGroup
    ? { fullPath: namespaceIdentifier }
    : { id: convertToGraphQLId(TYPE_ORGANIZATION, namespaceIdentifier) };

  return gqlClient()
    .query({ query, variables })
    .then(({ data }) => {
      const policyStore = isGroup ? data?.group?.policyStore : data?.organization?.policyStore;

      return (policyStore?.triggers ?? []).filter((trigger) => trigger?.id);
    })
    .catch(() => []);
};

// Unknown ids and unauthorized reads come back as an empty (or null) list
// rather than an error, so rejecting here is what keeps the not-found
// contract the detail and editor error states rely on.
const fetchStorePolicy = (namespaceType, namespaceIdentifier, policyId) => {
  const isGroup = namespaceType === NAMESPACE_TYPE_GROUP;
  const query = isGroup ? getGroupPolicyStorePolicies : getPolicyStorePolicies;
  const variables = isGroup
    ? { fullPath: namespaceIdentifier, ids: [Number(policyId)] }
    : { id: convertToGraphQLId(TYPE_ORGANIZATION, namespaceIdentifier), ids: [Number(policyId)] };

  return gqlClient()
    .query({
      query,
      variables,
      // A cached read could serve a policy another session has since changed,
      // so the editor and detail pages always load it from the network.
      fetchPolicy: 'network-only',
    })
    .then(({ data }) => {
      const policyStore = isGroup ? data.group?.policyStore : data.organization?.policyStore;
      const policy = policyStore?.policies?.[0];

      if (!policy) {
        // Constant Sentry-facing message, never rendered: an interpolated id
        // would split one ordinary not-found into an issue per policy.
        // eslint-disable-next-line @gitlab/require-i18n-strings
        throw new Error('Policy not found in the policy store');
      }

      // Shallow on purpose: the free-form JSON fields keep their stored shape.
      return convertObjectPropsToSnakeCase(policy, { dropKeys: ['__typename'] });
    });
};

/**
 * Fetches one policy through the GraphQL policies query, mapped the same way
 * as the list so the editor can read it back. Rejects on failure, including
 * for a policy the container does not have or the user cannot read.
 *
 * @param {string} namespaceType - NAMESPACE_TYPE_GROUP or NAMESPACE_TYPE_ORGANIZATION
 * @param {string|number} namespaceIdentifier - For groups: the full path (e.g. 'my-org/my-group').
 *   For organizations: the numeric ID.
 * @param {string|number} policyId
 * @returns {Promise<Object>}
 */
export const fetchPolicy = async (namespaceType, namespaceIdentifier, policyId) => {
  const [policy, remoteTriggers] = await Promise.all([
    fetchStorePolicy(namespaceType, namespaceIdentifier, policyId),
    fetchRemoteTriggers(namespaceType, namespaceIdentifier),
  ]);

  return toListPolicy(policy, remoteTriggers);
};

// The serializer emits the store's snake_case shape; these are the keys whose
// mutation argument is spelled differently. Only supplied keys are mapped: the
// update mutation keeps omitted fields and clears on an explicit null, so a
// missing policy_scope must not arrive as policyScope: null.
const MUTATION_VARIABLE_NAMES = {
  trigger_type: 'triggerType',
  policy_scope: 'policyScope',
  lifecycle_state: 'lifecycleState',
};

const declaredVariables = (document) =>
  new Set(
    document.definitions
      .find((definition) => definition.kind === 'OperationDefinition')
      .variableDefinitions.map((definition) => definition.variable.name.value),
  );

// The server ignores a variable the document does not declare, so a param
// nobody mapped would be dropped silently instead of failing. Each mutation
// declares its own set, so the check runs against the document being sent.
const toMutationVariables = (document, params) => {
  const declared = declaredVariables(document);

  return Object.fromEntries(
    Object.entries(params).map(([key, value]) => {
      const name = MUTATION_VARIABLE_NAMES[key] ?? key;

      if (!declared.has(name)) {
        throw new Error(`Policy store param not declared by the mutation: ${key}`);
      }

      return [name, value];
    }),
  );
};

/**
 * Creates a policy through the governPolicyCreate GraphQL mutation for
 * organizations, or through the REST API for groups. Rejects with a
 * PolicyStoreMutationError carrying the store's message when the params fail
 * validation, or with the request error on other failures.
 *
 * @param {string} namespaceType - NAMESPACE_TYPE_GROUP or NAMESPACE_TYPE_ORGANIZATION
 * @param {string|number} namespaceIdentifier - For groups: the full path (e.g. 'my-org/my-group').
 *   For organizations: the numeric ID.
 * @param {Object} params - Params from serializePolicyParams.
 * @returns {Promise<{id: number}>} The created policy.
 */
export const createPolicy = async (namespaceType, namespaceIdentifier, params) => {
  if (namespaceType === NAMESPACE_TYPE_GROUP) {
    const { data } = await Api.createGroupPolicyStorePolicy(namespaceIdentifier, params);
    return data;
  }

  const { data } = await gqlClient().mutate({
    mutation: governPolicyCreateMutation,
    variables: {
      // Params spread first so a stray organizationId in them cannot win.
      ...toMutationVariables(governPolicyCreateMutation, params),
      organizationId: convertToGraphQLId(TYPE_ORGANIZATION, namespaceIdentifier),
    },
  });

  const { policy, errors } = data.governPolicyCreate;

  if (errors.length) throw new PolicyStoreMutationError(errors.join(', '));

  return policy;
};

/**
 * Updates one policy through the REST API for groups, or through the
 * governPolicyUpdate GraphQL mutation for organizations. Only the supplied
 * params are sent, so the store keeps every other field as it is. Rejects with
 * a PolicyStoreMutationError carrying the store's message when the params fail
 * validation, or with the request error on other failures.
 *
 * @param {Object} options
 * @param {string} options.namespaceType - NAMESPACE_TYPE_GROUP or NAMESPACE_TYPE_ORGANIZATION
 * @param {string|number} options.namespaceIdentifier - For groups: the full path
 *   (e.g. 'my-org/my-group'). For organizations: the numeric ID.
 * @param {string|number} options.policyId
 * @param {Object} options.params - Params from serializePolicyParams, or a subset such
 *   as `{ lifecycle_state }` from the detail page's status toggle.
 * @returns {Promise<Object>} The updated policy, mapped like the list.
 */
export const updatePolicy = async ({ namespaceType, namespaceIdentifier, policyId, params }) => {
  if (namespaceType === NAMESPACE_TYPE_GROUP) {
    const [{ data }, remoteTriggers] = await Promise.all([
      Api.updateGroupPolicyStorePolicy(namespaceIdentifier, policyId, params),
      fetchRemoteTriggers(namespaceType, namespaceIdentifier),
    ]);

    return toListPolicy(data, remoteTriggers);
  }

  const [{ data }, remoteTriggers] = await Promise.all([
    gqlClient().mutate({
      mutation: governPolicyUpdateMutation,
      variables: {
        ...toMutationVariables(governPolicyUpdateMutation, params),
        organizationId: convertToGraphQLId(TYPE_ORGANIZATION, namespaceIdentifier),
        // Policy store ids are plain Ints at the GraphQL boundary, not GlobalIDs.
        policyId: Number(policyId),
      },
    }),
    fetchRemoteTriggers(namespaceType, namespaceIdentifier),
  ]);

  const { policy, errors } = data.governPolicyUpdate;

  if (errors.length) throw new PolicyStoreMutationError(errors.join(', '));

  // Shallow on purpose: the free-form JSON fields keep their stored shape.
  return toListPolicy(
    convertObjectPropsToSnakeCase(policy, { dropKeys: ['__typename'] }),
    remoteTriggers,
  );
};

/**
 * Deletes one policy through the REST API for groups, or through the
 * governPolicyDelete GraphQL mutation for organizations. Rejects with a
 * PolicyStoreMutationError carrying the store's message when the delete fails
 * validation, or with the request error on other failures.
 *
 * @param {Object} options
 * @param {string} options.namespaceType - NAMESPACE_TYPE_GROUP or NAMESPACE_TYPE_ORGANIZATION
 * @param {string|number} options.namespaceIdentifier - For groups: the full path
 *   (e.g. 'my-org/my-group'). For organizations: the numeric ID.
 * @param {string|number} options.policyId
 * @returns {Promise<void>}
 */
export const deletePolicy = async ({ namespaceType, namespaceIdentifier, policyId }) => {
  if (namespaceType === NAMESPACE_TYPE_GROUP) {
    await Api.deleteGroupPolicyStorePolicy(namespaceIdentifier, policyId);
    return;
  }

  const { data } = await gqlClient().mutate({
    mutation: governPolicyDeleteMutation,
    variables: {
      organizationId: convertToGraphQLId(TYPE_ORGANIZATION, namespaceIdentifier),
      // Policy store ids are plain Ints at the GraphQL boundary, not GlobalIDs.
      id: Number(policyId),
    },
  });

  const { errors } = data.governPolicyDelete;

  if (errors.length) throw new PolicyStoreMutationError(errors.join(', '));
};
