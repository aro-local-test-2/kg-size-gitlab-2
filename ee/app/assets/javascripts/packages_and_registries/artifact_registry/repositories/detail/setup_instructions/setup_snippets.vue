<script>
import { GlLink, GlSprintf } from '@gitlab/ui';
import { SETUP_SECTION_INSTALL, SETUP_SECTION_PUBLISH } from '../../../constants';
import { buildRepositoryClientUrl } from '../../../utils';
import SnippetCodeBlock from '../../../components/snippet_code_block.vue';
import { setupSnippetSections } from './snippets';

export default {
  name: 'ArtifactRegistrySetupSnippets',
  components: {
    GlLink,
    GlSprintf,
    SnippetCodeBlock,
  },
  inject: ['slug', 'clientBaseUrl'],
  props: {
    name: {
      type: String,
      required: true,
    },
    format: {
      type: String,
      required: true,
    },
    tool: {
      type: String,
      required: true,
    },
    section: {
      type: String,
      required: false,
      default: SETUP_SECTION_INSTALL,
      validator: (value) => [SETUP_SECTION_INSTALL, SETUP_SECTION_PUBLISH].includes(value),
    },
  },
  computed: {
    repositoryUrl() {
      const { clientBaseUrl, slug, format, name } = this;

      return buildRepositoryClientUrl({ clientBaseUrl, slug, format, name });
    },
    sections() {
      const { format, tool, section, slug, name, repositoryUrl } = this;

      return setupSnippetSections({ format, tool, section, slug, name, repositoryUrl });
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-5">
    <section
      v-for="(setupSection, sectionIndex) in sections"
      :key="sectionIndex"
      class="gl-flex gl-flex-col gl-gap-5"
      data-testid="setup-section"
    >
      <h3 v-if="setupSection.heading" class="gl-heading-4 gl-mb-0">{{ setupSection.heading }}</h3>

      <div
        v-for="(block, blockIndex) in setupSection.blocks"
        :key="blockIndex"
        data-testid="setup-block"
      >
        <p class="gl-mb-3">
          <gl-sprintf :message="block.text">
            <template #code="{ content }">
              <code>{{ content }}</code>
            </template>
            <template #link="{ content }">
              <gl-link :href="block.link" target="_blank">{{ content }}</gl-link>
            </template>
          </gl-sprintf>
        </p>

        <snippet-code-block v-if="block.code" :snippet="block.code" :copy-text="block.copyText" />
      </div>
    </section>
  </div>
</template>
