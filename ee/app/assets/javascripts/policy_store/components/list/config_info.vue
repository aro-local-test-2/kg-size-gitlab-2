<script>
import { GlBadge } from '@gitlab/ui';
import { s__ } from '~/locale';
import { ACTIONS } from '../../catalog/actions';
import { RULES } from '../../catalog/rules';
import { resolveCatalogEntry } from '../../catalog/helpers';
import { ENFORCEMENT_MODES } from '../editor/constants';
import { deserializePolicyData } from '../editor/serializer';
import { modeLabel, modeVariant, statusLabel, statusVariant } from './utils';
import ConfigInfoSection from './config_info_section.vue';

export default {
  name: 'PolicyConfigInfo',
  components: {
    ConfigInfoSection,
    GlBadge,
  },
  i18n: {
    mode: s__('PolicyStore|Mode'),
    status: s__('PolicyStore|Status'),
    rules: s__('PolicyStore|Rules'),
    actions: s__('PolicyStore|Actions'),
    noRules: s__('PolicyStore|No rules configured'),
    noActions: s__('PolicyStore|No actions configured'),
  },
  props: {
    policy: {
      type: Object,
      required: true,
    },
  },
  computed: {
    // The plain-language effect of the current mode, from the same definitions
    // the editor's mode selector shows.
    modeDescription() {
      return ENFORCEMENT_MODES.find(({ value }) => value === this.policy.mode)?.description || '';
    },
    sections() {
      const { rules, ruleConfigs, actions, actionConfigs } = deserializePolicyData(this.policy);

      return [
        {
          testid: 'rules',
          label: this.$options.i18n.rules,
          emptyLabel: this.$options.i18n.noRules,
          entries: rules.map((id) => resolveCatalogEntry(RULES, id, ruleConfigs[id])),
        },
        {
          testid: 'actions',
          label: this.$options.i18n.actions,
          emptyLabel: this.$options.i18n.noActions,
          entries: actions.map((id) => resolveCatalogEntry(ACTIONS, id, actionConfigs[id])),
        },
      ];
    },
  },
  methods: {
    modeLabel,
    modeVariant,
    statusLabel,
    statusVariant,
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-4 gl-py-3" data-testid="config-info">
    <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-5">
      <span>
        <span class="gl-mr-2 gl-text-sm gl-font-semibold">{{ $options.i18n.mode }}</span>
        <gl-badge :variant="modeVariant(policy.mode)" data-testid="config-info-mode">
          {{ modeLabel(policy.mode) }}
        </gl-badge>
        <span class="gl-ml-2 gl-text-sm gl-text-subtle" data-testid="config-info-mode-description">
          {{ modeDescription }}
        </span>
      </span>
      <span>
        <span class="gl-mr-2 gl-text-sm gl-font-semibold">{{ $options.i18n.status }}</span>
        <gl-badge :variant="statusVariant(policy.status)" data-testid="config-info-status">
          {{ statusLabel(policy.status) }}
        </gl-badge>
      </span>
    </div>

    <config-info-section
      v-for="section in sections"
      :key="section.testid"
      :testid="`config-info-${section.testid}`"
      :label="section.label"
      :empty-label="section.emptyLabel"
      :entries="section.entries"
    />
  </div>
</template>
