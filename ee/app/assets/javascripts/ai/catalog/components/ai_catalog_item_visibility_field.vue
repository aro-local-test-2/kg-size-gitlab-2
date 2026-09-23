<script>
import { GlBadge } from '@gitlab/ui';
import {
  VISIBILITY_TYPE_ICON,
  VISIBILITY_LEVEL_LABELS,
  VISIBILITY_LEVEL_BADGE_VARIANT,
} from '../constants';
import AiCatalogItemField from './ai_catalog_item_field.vue';

export default {
  name: 'AiCatalogItemVisibilityField',
  components: {
    GlBadge,
    AiCatalogItemField,
  },
  props: {
    visibility: {
      type: String,
      required: true,
    },
    descriptionTexts: {
      type: Object,
      required: true,
    },
  },
  computed: {
    visibilityDescription() {
      return this.descriptionTexts[this.visibility];
    },
    badgeIcon() {
      return VISIBILITY_TYPE_ICON[this.visibility];
    },
    badgeLabel() {
      return VISIBILITY_LEVEL_LABELS[this.visibility];
    },
    badgeVariant() {
      return VISIBILITY_LEVEL_BADGE_VARIANT[this.visibility];
    },
  },
};
</script>

<template>
  <ai-catalog-item-field :title="s__('AICatalog|Visibility')">
    <div class="gl-text-subtle">
      {{ visibilityDescription }}
    </div>
    <gl-badge :icon="badgeIcon" :variant="badgeVariant" class="gl-mt-3">
      {{ badgeLabel }}
    </gl-badge>
  </ai-catalog-item-field>
</template>
