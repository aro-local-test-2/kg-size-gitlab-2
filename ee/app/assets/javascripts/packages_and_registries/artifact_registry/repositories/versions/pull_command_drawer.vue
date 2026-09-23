<script>
import { GlCollapsibleListbox, GlLink, GlSprintf } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import InstructionsDrawer from '../../components/instructions_drawer.vue';
import SnippetCodeBlock from '../../components/snippet_code_block.vue';
import { REPOSITORY_FORMAT_HELP_PATHS } from '../../constants';
import { buildRepositoryClientUrl, shortDigest } from '../../utils';
import { PULL_SECTION_TAG, pullSnippetSections } from './pull_snippets';

export default {
  name: 'ArtifactRegistryPullCommandDrawer',
  components: {
    CrudComponent,
    GlCollapsibleListbox,
    GlLink,
    GlSprintf,
    InstructionsDrawer,
    SnippetCodeBlock,
  },
  inject: ['slug', 'clientBaseUrl'],
  props: {
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
    format: {
      type: String,
      required: true,
    },
    artifact: {
      type: Object,
      required: true,
    },
    name: {
      type: String,
      required: true,
    },
    version: {
      type: String,
      required: false,
      default: '',
    },
    digest: {
      type: String,
      required: false,
      default: '',
    },
    tags: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['close'],
  data() {
    return {
      selectedTag: null,
      tagLabelId: uniqueId('pull-command-tag-label-'),
    };
  },
  computed: {
    activeTag() {
      return this.tags.includes(this.selectedTag) ? this.selectedTag : (this.tags[0] ?? '');
    },
    tagItems() {
      return this.tags.map((tag) => ({ value: tag, text: tag }));
    },
    hasTagSelector() {
      return this.tags.length > 1;
    },
    repositoryUrl() {
      const { clientBaseUrl, slug, format, name } = this;

      return buildRepositoryClientUrl({ clientBaseUrl, slug, format, name });
    },
    sections() {
      const { format, artifact, version, activeTag: tag, digest, repositoryUrl } = this;

      return pullSnippetSections({ format, artifact, version, tag, digest, repositoryUrl });
    },
    helpPath() {
      return REPOSITORY_FORMAT_HELP_PATHS[this.format];
    },
    accessibleTitle() {
      if (this.digest) {
        return sprintf(s__('ArtifactRegistry|Pull command for %{digest}'), {
          digest: shortDigest(this.digest),
        });
      }

      return sprintf(s__('ArtifactRegistry|Pull command for %{version}'), {
        version: this.version,
      });
    },
  },
  methods: {
    isTagSection({ key }) {
      return key === PULL_SECTION_TAG;
    },
  },
};
</script>

<template>
  <instructions-drawer
    :title="s__('ArtifactRegistry|Pull command')"
    :accessible-title="accessibleTitle"
    :open="open"
    @close="$emit('close')"
  >
    <div class="gl-flex gl-flex-col gl-gap-5">
      <crud-component
        v-for="(section, sectionIndex) in sections"
        :key="sectionIndex"
        :title="section.heading"
        title-tag="h3"
        data-testid="pull-command-section"
        body-class="!gl-p-0"
      >
        <template v-if="hasTagSelector && isTagSection(section)" #actions>
          <span :id="tagLabelId" class="gl-sr-only">{{ s__('ArtifactRegistry|Tag') }}</span>
          <gl-collapsible-listbox
            :items="tagItems"
            :selected="activeTag"
            :toggle-aria-labelled-by="tagLabelId"
            size="small"
            data-testid="pull-command-tag-selector"
            @select="selectedTag = $event"
          />
        </template>

        <div class="gl-flex gl-flex-col gl-gap-4">
          <snippet-code-block
            v-for="(block, blockIndex) in section.blocks"
            :key="blockIndex"
            :snippet="block.code"
            :copy-text="block.copyText"
          />
        </div>
      </crud-component>

      <p v-if="helpPath" class="gl-mb-0 gl-text-subtle" data-testid="pull-command-help">
        <gl-sprintf
          :message="
            s__(
              'ArtifactRegistry|For more information, %{linkStart}see the documentation%{linkEnd}.',
            )
          "
        >
          <template #link="{ content }">
            <gl-link :href="helpPath">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </p>
    </div>
  </instructions-drawer>
</template>
