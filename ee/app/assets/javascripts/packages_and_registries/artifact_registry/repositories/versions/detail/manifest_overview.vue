<script>
import { s__ } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { SETUP_SECTION_INSTALL } from '../../../constants';
import SnippetCodeBlock from '../../../components/snippet_code_block.vue';
import { buildRepositoryClientUrl } from '../../../utils';
import { setupSnippetSections } from '../../detail/setup_instructions/snippets';

export default {
  name: 'ArtifactRegistryManifestOverview',
  components: {
    CrudComponent,
    SnippetCodeBlock,
  },
  inject: ['slug', 'clientBaseUrl'],
  props: {
    format: {
      type: String,
      required: true,
    },
    name: {
      type: String,
      required: true,
    },
    imageName: {
      type: String,
      required: false,
      default: '',
    },
    manifest: {
      type: Object,
      required: true,
    },
  },
  computed: {
    repositoryUrl() {
      const { clientBaseUrl, slug, format, name } = this;

      return buildRepositoryClientUrl({ clientBaseUrl, slug, format, name });
    },
    blocks() {
      const { imageName, manifest } = this;

      // No digest: the builder falls through to its generic pull image:tag arm, with a placeholder
      // tag when untagged. It already refuses an empty image name, so the guard is an explicit
      // route to the unavailable message rather than a correctness requirement.
      if (!imageName || !manifest.digest) return [];

      // First section only: the second is the registry-setup block with the glab login command.
      const [pullSection] = setupSnippetSections({
        format: this.format,
        section: SETUP_SECTION_INSTALL,
        name: this.name,
        repositoryUrl: this.repositoryUrl,
        imageName,
        tag: manifest.tags?.[0] ?? null,
        digest: manifest.digest,
      });

      return pullSection?.blocks ?? [];
    },
    hasCommands() {
      return this.blocks.length > 0;
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|Pull commands are unavailable for this manifest.'),
  },
};
</script>

<template>
  <div v-if="hasCommands" class="gl-flex gl-flex-col gl-gap-5" data-testid="manifest-pull-commands">
    <crud-component
      v-for="block in blocks"
      :key="block.text"
      :title="block.text"
      body-class="!gl-p-0"
      data-testid="pull-command-panel"
    >
      <snippet-code-block :snippet="block.code" :copy-text="block.copyText" />
    </crud-component>
  </div>

  <p v-else class="gl-mb-0 gl-text-subtle" data-testid="pull-commands-unavailable">
    {{ $options.i18n.unavailable }}
  </p>
</template>
