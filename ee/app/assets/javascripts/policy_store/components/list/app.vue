<script>
import { GlAlert } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { __, s__ } from '~/locale';
import { joinPaths } from '~/lib/utils/url_utility';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPE_ORGANIZATION } from '~/graphql_shared/constants';
import { toListPolicies, NAMESPACE_TYPE_GROUP } from '../../policies';
import { startOfReportingWindow, toEvaluationsCount } from '../../evaluations';
import getPolicyStorePolicies from '../../graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStorePolicies from '../../graphql/get_group_policy_store_policies.query.graphql';
import getPolicyEvaluationsCount from '../../graphql/get_policy_evaluations_count.query.graphql';
import ListWrapper from './list_wrapper.vue';

export default {
  name: 'PolicyStoreListRoot',
  components: {
    GlAlert,
    ListWrapper,
  },
  i18n: {
    policiesError: s__('PolicyStore|The policies could not be fetched from the Policy Store API.'),
    retry: __('Retry'),
    policiesPermissionError: s__('PolicyStore|You do not have permission to view the policies.'),
  },
  // The per-policy detail path is derived from listPath and the policy id until the API exposes it.
  inject: {
    organizationId: {},
    namespacePath: { default: '' },
    namespaceType: {},
    newPolicyPath: { default: '' },
    listPath: { default: '' },
  },
  data() {
    return {
      policies: [],
      policiesError: false,
      policiesErrorPermission: false,
      recentEvaluationsCount: null,
      recentEvaluationsError: false,
    };
  },
  apollo: {
    policies: {
      query() {
        return this.isGroupContext ? getGroupPolicyStorePolicies : getPolicyStorePolicies;
      },
      variables() {
        return this.isGroupContext
          ? { fullPath: this.namespacePath }
          : { id: convertToGraphQLId(TYPE_ORGANIZATION, this.organizationId) };
      },
      update(data) {
        return toListPolicies(this.policyStoreFrom(data));
      },
      result({ data, error }) {
        // A failed refetch re-emits the last cached data with the error
        // attached; skip it so the error state set by the hook below survives.
        if (!data || error) return;

        // Denied reads return null instead of an error — the resolver nulls the
        // field when the viewer lacks read_govern_policy or the experiment is
        // off — so a null list is the only permission signal the API gives.
        const denied = !this.policyStoreFrom(data)?.policies;
        this.policiesError = denied;
        this.policiesErrorPermission = denied;
      },
      error(error) {
        Sentry.captureException(error);
        this.policiesError = true;
      },
    },
    // The stat gets no error state of its own, but it must not answer with a
    // confident 0 when the read failed: null renders as a placeholder while
    // the policies query keeps ownership of the page error. Skipped for groups
    // until a group-scoped evaluations field exists — the organization query
    // would either fail for a user without org read, or show the whole org's
    // count on a group page.
    recentEvaluationsCount: {
      query: getPolicyEvaluationsCount,
      skip() {
        return this.isGroupContext;
      },
      variables() {
        return this.evaluationsVariables();
      },
      update({ organization }) {
        return toEvaluationsCount(organization?.policyStore?.policyEvaluations);
      },
      error(error) {
        Sentry.captureException(error);
        this.recentEvaluationsError = true;
      },
    },
  },
  computed: {
    isGroupContext() {
      return this.namespaceType === NAMESPACE_TYPE_GROUP;
    },
    policiesLoading() {
      return this.$apollo.queries.policies.loading;
    },
    recentEvaluationsLoading() {
      return this.$apollo.queries.recentEvaluationsCount.loading;
    },
    // A failed refetch leaves Apollo re-emitting the last cached count, so the
    // error flag rather than the value decides whether the tile can show it.
    recentEvaluations() {
      return this.recentEvaluationsError ? null : this.recentEvaluationsCount;
    },
    listPolicies() {
      // A failed refetch leaves Apollo re-emitting the last cached rows; guard
      // here so an error never shows stale data, matching the REST version.
      if (this.policiesError) return [];

      return this.policies.map((policy) => ({
        ...policy,
        detailPath: this.listPath ? joinPaths(this.listPath, String(policy.id)) : '',
      }));
    },
    policiesErrorMessage() {
      return this.policiesErrorPermission
        ? this.$options.i18n.policiesPermissionError
        : this.$options.i18n.policiesError;
    },
    // Retrying cannot fix missing permissions, so the button only shows for
    // failures that might be transient.
    policiesErrorRetryText() {
      return this.policiesErrorPermission ? null : this.$options.i18n.retry;
    },
  },
  methods: {
    policyStoreFrom(data) {
      return this.isGroupContext ? data?.group?.policyStore : data?.organization?.policyStore;
    },
    evaluationsVariables() {
      return {
        id: convertToGraphQLId(TYPE_ORGANIZATION, this.organizationId),
        evaluatedAfter: startOfReportingWindow(),
      };
    },
    retry() {
      this.policiesError = false;
      this.policiesErrorPermission = false;
      this.recentEvaluationsError = false;
      // A failed retry rejects the refetch promise; the error() hook already
      // handles it, so consume the rejection to avoid an unhandled one.
      this.$apollo.queries.policies.refetch().catch(() => {});
      // The stat can fail on its own, so Retry has to cover it too. Pass the
      // variables explicitly: a bare refetch() reuses the boundary computed at
      // mount, so a tab left open past UTC midnight would keep asking for
      // yesterday's window. Skipped for groups — the evaluations query is
      // org-only until a group-scoped field exists.
      if (!this.isGroupContext) {
        this.$apollo.queries.recentEvaluationsCount
          .refetch(this.evaluationsVariables())
          .catch(() => {});
      }
    },
  },
};
</script>

<template>
  <div>
    <gl-alert
      v-if="policiesError"
      variant="danger"
      :dismissible="false"
      :primary-button-text="policiesErrorRetryText"
      class="gl-mt-4"
      data-testid="policies-error"
      @primary-action="retry()"
    >
      {{ policiesErrorMessage }}
    </gl-alert>
    <list-wrapper
      :policies="listPolicies"
      :loading="policiesLoading"
      :error="policiesError"
      :recent-evaluations="recentEvaluations"
      :recent-evaluations-loading="recentEvaluationsLoading"
      :new-policy-path="newPolicyPath"
    />
  </div>
</template>
