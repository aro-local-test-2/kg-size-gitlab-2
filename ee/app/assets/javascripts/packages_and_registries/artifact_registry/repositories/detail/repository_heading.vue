<script>
import { GlBadge, GlButton, GlIcon, GlTooltipDirective, GlTruncate } from '@gitlab/ui';
import {
  REPOSITORY_FORMAT_LABELS,
  REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
  REPOSITORY_KIND_LABELS,
  REPOSITORY_KIND_REMOTE,
  REPOSITORY_VISIBILITY_ICONS,
  REPOSITORY_VISIBILITY_LABELS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import { s__ } from '~/locale';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import FormatLogo from '../components/format_logo.vue';

export default {
  name: 'ArtifactRegistryRepositoryHeading',
  components: {
    ClipboardButton,
    FormatLogo,
    GlBadge,
    GlButton,
    GlIcon,
    GlTruncate,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    repository: {
      type: Object,
      required: true,
    },
  },
  computed: {
    formatLabel() {
      return REPOSITORY_FORMAT_LABELS[this.repository.format];
    },
    kindLabel() {
      return REPOSITORY_KIND_LABELS[this.repository.kind];
    },
    visibilityIcon() {
      return REPOSITORY_VISIBILITY_ICONS[this.repository.visibility];
    },
    visibilityLabel() {
      return REPOSITORY_VISIBILITY_LABELS[this.repository.visibility];
    },
    isRemote() {
      return this.repository.kind === REPOSITORY_KIND_REMOTE;
    },
    upstreamUrl() {
      return this.repository.settings?.url ?? '';
    },
  },
  i18n: {
    upstreamUrlLabel: s__('ArtifactRegistry|Upstream URL'),
    upstreamUrlCopyAriaLabel: s__('ArtifactRegistry|Copy upstream URL'),
  },
  logoSize: REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
};
</script>

<template>
  <div class="gl-flex gl-items-center gl-gap-3">
    <format-logo
      :format="repository.format"
      :size="$options.logoSize"
      data-testid="repository-format-logo"
    />
    <span class="gl-sr-only" data-testid="repository-format-name">{{ formatLabel }}</span>

    <div class="gl-flex gl-min-w-0 gl-grow gl-flex-col">
      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
        <h1 class="gl-heading-1 !gl-m-0" data-testid="page-heading">
          <span class="gl-wrap-anywhere" data-testid="repository-name">{{ repository.name }}</span>
        </h1>
        <gl-button
          v-gl-tooltip
          :title="visibilityLabel"
          :aria-label="visibilityLabel"
          category="tertiary"
          size="small"
          class="!gl-min-h-5 !gl-min-w-5 !gl-p-0"
          data-testid="repository-visibility"
        >
          <gl-icon :name="visibilityIcon" variant="subtle" />
        </gl-button>
        <gl-badge>{{ kindLabel }}</gl-badge>
      </div>
      <div
        v-if="isRemote && upstreamUrl"
        class="gl-flex gl-min-w-0 gl-max-w-30 gl-items-center gl-gap-3 gl-text-subtle @md:gl-max-w-md"
        data-testid="upstream-url"
      >
        <span class="gl-sr-only" data-testid="upstream-url-label">{{
          $options.i18n.upstreamUrlLabel
        }}</span>
        <gl-truncate :text="upstreamUrl" position="middle" with-tooltip />
        <clipboard-button
          :text="upstreamUrl"
          :title="$options.i18n.upstreamUrlCopyAriaLabel"
          category="tertiary"
          size="small"
          class="gl-shrink-0"
        />
      </div>
    </div>
  </div>
</template>
