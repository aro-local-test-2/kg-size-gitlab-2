<script>
import {
  GlAlert,
  GlBadge,
  GlButton,
  GlExperimentBadge,
  GlLoadingIcon,
  GlSprintf,
} from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { createAlert } from '~/alert';
import { s__, __, sprintf } from '~/locale';
import { visitUrl } from '~/lib/utils/url_utility';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import { ACTIONS } from '../../catalog/actions';
import { RULES } from '../../catalog/rules';
import { TRIGGERS } from '../../catalog/triggers';
import { resolveCatalogEntry } from '../../catalog/helpers';
import { POLICY_STATUS_ACTIVE, POLICY_STATUS_DISABLED } from '../../constants';
import { fetchPolicy, updatePolicy, deletePolicy, NAMESPACE_TYPE_GROUP } from '../../policies';
import { apiErrorMessage } from '../../utils';
import { deserializePolicyData } from '../editor/serializer';
import { modeLabel, modeVariant, statusLabel, statusVariant, scopeLabel } from '../list/utils';
import SummarySection from './summary_section.vue';

export default {
  name: 'PolicyStoreDetailRoot',
  components: {
    GlAlert,
    GlBadge,
    GlButton,
    GlExperimentBadge,
    GlLoadingIcon,
    GlSprintf,
    SummarySection,
    TimeAgoTooltip,
  },
  i18n: {
    policyError: s__(
      'PolicyStore|The policy could not be loaded from the Policy Store API. Refresh the page to try again.',
    ),
    deleteError: s__('PolicyStore|The policy could not be deleted. Try again.'),
    deleteConfirmTitle: s__('PolicyStore|Delete policy?'),
    deleteConfirmMessage: s__(
      'PolicyStore|Are you sure you want to delete %{name}? This action cannot be undone.',
    ),
    deleteConfirmButton: __('Delete'),
    editPolicy: s__('PolicyStore|Edit policy'),
    disablePolicy: s__('PolicyStore|Disable'),
    enablePolicy: s__('PolicyStore|Enable'),
    toggleStatusError: s__('PolicyStore|The policy could not be updated. Try again.'),
    trigger: s__('PolicyStore|Trigger'),
    rules: s__('PolicyStore|Rules'),
    actions: s__('PolicyStore|Actions'),
    scope: s__('PolicyStore|Scope'),
    scopeRego: s__('PolicyStore|Compiled scope Rego'),
    scopeRegoHelp: s__(
      'PolicyStore|Read-only Rego the store compiled from the scope. The policy engine evaluates this program to decide where the policy applies.',
    ),
    policyRego: s__('PolicyStore|Compiled policy Rego'),
    policyRegoHelp: s__(
      'PolicyStore|Read-only Rego the store compiled from the rules. The policy engine evaluates this single program when the trigger fires.',
    ),
    version: s__('PolicyStore|Version %{version}'),
    created: s__('PolicyStore|Created %{timeAgo}'),
    updated: s__('PolicyStore|Updated %{timeAgo}'),
  },
  inject: {
    organizationId: {},
    namespacePath: { default: '' },
    namespaceType: {},
    policyId: {},
    listPath: { default: '' },
    editPath: { default: '' },
  },
  data() {
    return {
      policy: null,
      policyLoading: false,
      policyError: false,
      deleting: false,
      toggling: false,
    };
  },
  computed: {
    isGroupContext() {
      return this.namespaceType === NAMESPACE_TYPE_GROUP;
    },
    namespaceIdentifier() {
      return this.isGroupContext ? this.namespacePath : this.organizationId;
    },
    isActive() {
      return this.policy.status === POLICY_STATUS_ACTIVE;
    },
    versionLabel() {
      return sprintf(this.$options.i18n.version, { version: this.policy.version });
    },
    hasMeta() {
      return Boolean(this.policy.version || this.policy.created_at || this.policy.updated_at);
    },
    regoSections() {
      return [
        {
          testid: 'scope-rego',
          label: this.$options.i18n.scopeRego,
          help: this.$options.i18n.scopeRegoHelp,
          rego: this.policy.scope_rego,
        },
        {
          testid: 'policy-rego',
          label: this.$options.i18n.policyRego,
          help: this.$options.i18n.policyRegoHelp,
          rego: this.policy.policy_rego,
        },
      ].filter(({ rego }) => rego);
    },
    toggleStatusLabel() {
      return this.isActive ? this.$options.i18n.disablePolicy : this.$options.i18n.enablePolicy;
    },
    // The catalog files supply the presentation for the persisted ids, the same
    // lookup the editor and the list use.
    sections() {
      const { trigger, triggerConfig, rules, ruleConfigs, actions, actionConfigs } =
        deserializePolicyData(this.policy);

      return [
        {
          testid: 'trigger',
          label: this.$options.i18n.trigger,
          ids: trigger ? [trigger] : [],
          catalog: TRIGGERS,
          configs: { [trigger]: triggerConfig },
        },
        {
          testid: 'rules',
          label: this.$options.i18n.rules,
          ids: rules,
          catalog: RULES,
          configs: ruleConfigs,
        },
        {
          testid: 'actions',
          label: this.$options.i18n.actions,
          ids: actions,
          catalog: ACTIONS,
          configs: actionConfigs,
        },
      ].map(({ testid, label, ids, catalog, configs }) => ({
        testid,
        label,
        entries: ids.map((id) => resolveCatalogEntry(catalog, id, configs[id])),
      }));
    },
  },
  created() {
    this.loadPolicy();
  },
  methods: {
    modeLabel,
    modeVariant,
    statusLabel,
    statusVariant,
    scopeLabel,
    async loadPolicy() {
      this.policyLoading = true;

      try {
        this.policy = await fetchPolicy(
          this.namespaceType,
          this.namespaceIdentifier,
          this.policyId,
        );
      } catch (error) {
        Sentry.captureException(error);
        this.policyError = true;
      } finally {
        this.policyLoading = false;
      }
    },
    async onToggleStatus() {
      this.toggling = true;

      const lifecycleState = this.isActive ? POLICY_STATUS_DISABLED : POLICY_STATUS_ACTIVE;

      try {
        this.policy = await updatePolicy({
          namespaceType: this.namespaceType,
          namespaceIdentifier: this.namespaceIdentifier,
          policyId: this.policyId,
          params: { lifecycle_state: lifecycleState },
        });
      } catch (error) {
        Sentry.captureException(error);
        createAlert({ message: apiErrorMessage(error) || this.$options.i18n.toggleStatusError });
      } finally {
        this.toggling = false;
      }
    },
    async onDelete() {
      // Guards re-entrancy: the confirm dialog is awaited before any request,
      // so without this a double-click would open two confirmation flows.
      if (this.deleting) return;

      this.deleting = true;

      const confirmed = await confirmAction(
        sprintf(this.$options.i18n.deleteConfirmMessage, { name: this.policy.name }),
        {
          title: this.$options.i18n.deleteConfirmTitle,
          primaryBtnText: this.$options.i18n.deleteConfirmButton,
          primaryBtnVariant: 'danger',
        },
      );

      if (!confirmed) {
        this.deleting = false;
        return;
      }

      try {
        await deletePolicy({
          namespaceType: this.namespaceType,
          namespaceIdentifier: this.namespaceIdentifier,
          policyId: this.policyId,
        });

        if (this.listPath) {
          visitUrl(this.listPath);
        } else {
          this.deleting = false;
        }
      } catch (error) {
        Sentry.captureException(error);
        createAlert({ message: apiErrorMessage(error) || this.$options.i18n.deleteError });
        this.deleting = false;
      }
    },
  },
};
</script>

<template>
  <gl-loading-icon v-if="policyLoading" size="lg" class="gl-mt-6" data-testid="policy-loading" />
  <gl-alert
    v-else-if="policyError"
    variant="danger"
    :dismissible="false"
    class="gl-mt-4"
    data-testid="policy-error"
  >
    {{ $options.i18n.policyError }}
  </gl-alert>
  <div v-else-if="policy" class="gl-flex gl-flex-col gl-gap-5 gl-pt-6">
    <div class="gl-flex gl-flex-wrap gl-items-start gl-justify-between gl-gap-4">
      <div class="gl-min-w-0">
        <div class="gl-mb-2 gl-flex gl-items-center">
          <h1 class="gl-heading-1 gl-mb-0" data-testid="policy-name">{{ policy.name }}</h1>
          <gl-experiment-badge type="experiment" />
        </div>
        <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
          <gl-badge variant="neutral" data-testid="policy-type">{{ policy.type }}</gl-badge>
          <gl-badge :variant="modeVariant(policy.mode)" data-testid="policy-mode">
            {{ modeLabel(policy.mode) }}
          </gl-badge>
          <gl-badge :variant="statusVariant(policy.status)" data-testid="policy-status">
            {{ statusLabel(policy.status) }}
          </gl-badge>
        </div>
        <p
          v-if="policy.description"
          class="gl-mb-0 gl-mt-3 gl-text-subtle"
          data-testid="policy-description"
        >
          {{ policy.description }}
        </p>
        <ul
          v-if="hasMeta"
          class="gl-mb-0 gl-mt-3 gl-flex gl-list-none gl-flex-wrap gl-gap-x-4 gl-gap-y-1 gl-p-0 gl-text-sm gl-text-subtle"
          data-testid="policy-meta"
        >
          <li v-if="policy.version" data-testid="policy-version">{{ versionLabel }}</li>
          <li v-if="policy.created_at" data-testid="policy-created-at">
            <gl-sprintf :message="$options.i18n.created">
              <template #timeAgo><time-ago-tooltip :time="policy.created_at" /></template>
            </gl-sprintf>
          </li>
          <li v-if="policy.updated_at" data-testid="policy-updated-at">
            <gl-sprintf :message="$options.i18n.updated">
              <template #timeAgo><time-ago-tooltip :time="policy.updated_at" /></template>
            </gl-sprintf>
          </li>
        </ul>
      </div>
      <div class="gl-flex gl-flex-shrink-0 gl-gap-3">
        <gl-button :href="editPath" data-testid="edit-policy-button">
          {{ $options.i18n.editPolicy }}
        </gl-button>
        <gl-button :loading="toggling" data-testid="toggle-status-button" @click="onToggleStatus">
          {{ toggleStatusLabel }}
        </gl-button>
        <gl-button
          category="secondary"
          variant="danger"
          :loading="deleting"
          data-testid="delete-policy-button"
          @click="onDelete"
        >
          {{ $options.i18n.deleteConfirmButton }}
        </gl-button>
      </div>
    </div>

    <summary-section
      v-for="section in sections"
      :key="section.testid"
      :label="section.label"
      :entries="section.entries"
      :testid="section.testid"
    />

    <summary-section :label="$options.i18n.scope" testid="scope">
      <p class="gl-mb-0">{{ scopeLabel(policy.scopedProjectsCount) }}</p>
    </summary-section>

    <summary-section
      v-for="rego in regoSections"
      :key="rego.testid"
      :label="rego.label"
      :testid="rego.testid"
    >
      <p class="gl-mb-3 gl-text-sm gl-text-subtle">{{ rego.help }}</p>
      <pre
        tabindex="0"
        role="region"
        :aria-label="rego.label"
        class="gl-mb-0 gl-max-h-48 gl-overflow-y-auto gl-whitespace-pre-wrap gl-rounded-base gl-bg-subtle gl-p-3 gl-text-sm"
      ><code>{{ rego.rego }}</code></pre>
    </summary-section>
  </div>
</template>
