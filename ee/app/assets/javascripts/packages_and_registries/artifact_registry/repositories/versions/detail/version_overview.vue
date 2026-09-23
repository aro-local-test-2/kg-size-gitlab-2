<script>
import { GlLink, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import SnippetCodeBlock from '../../../components/snippet_code_block.vue';
import {
  REPOSITORY_FORMAT_HELP_PATHS,
  REPOSITORY_FORMAT_MAVEN,
  REPOSITORY_FORMAT_NPM,
  SETUP_TOOLS,
} from '../../../constants';
import { installSnippetBlock } from '../../detail/setup_instructions/snippets';
import ToolSelector from '../../detail/setup_instructions/tool_selector.vue';
import { artifactDisplayName, buildRepositoryClientUrl } from '../../../utils';

const HELP = {
  [REPOSITORY_FORMAT_MAVEN]: {
    path: REPOSITORY_FORMAT_HELP_PATHS[REPOSITORY_FORMAT_MAVEN],
    text: s__(
      'ArtifactRegistry|For more information on the Maven registry, %{linkStart}see the documentation%{linkEnd}.',
    ),
  },
  [REPOSITORY_FORMAT_NPM]: {
    path: REPOSITORY_FORMAT_HELP_PATHS[REPOSITORY_FORMAT_NPM],
    text: s__(
      'ArtifactRegistry|For more information on the npm registry, %{linkStart}see the documentation%{linkEnd}.',
    ),
  },
};

export default {
  name: 'ArtifactRegistryVersionOverview',
  components: {
    CrudComponent,
    GlLink,
    GlSprintf,
    SnippetCodeBlock,
    ToolSelector,
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
    artifact: {
      type: Object,
      required: false,
      default: null,
    },
    version: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      selectedTool: null,
    };
  },
  computed: {
    tools() {
      return SETUP_TOOLS[this.format] ?? [];
    },
    activeTool() {
      const selected = this.tools.find(({ value }) => value === this.selectedTool);

      return selected?.value ?? this.tools[0]?.value ?? '';
    },
    help() {
      return HELP[this.format];
    },
    repositoryUrl() {
      const { clientBaseUrl, slug, format, name } = this;

      return buildRepositoryClientUrl({ clientBaseUrl, slug, format, name });
    },
    coordinates() {
      if (this.format === REPOSITORY_FORMAT_MAVEN) {
        return {
          groupId: this.artifact?.groupId ?? null,
          artifactId: this.artifact?.artifactId ?? null,
        };
      }

      return { packageName: artifactDisplayName(this.artifact, this.format) || null };
    },
    block() {
      const { format, activeTool: tool, name, repositoryUrl, coordinates } = this;

      return installSnippetBlock({
        format,
        tool,
        name,
        repositoryUrl,
        version: this.version.version ?? null,
        ...coordinates,
      });
    },
  },
};
</script>

<template>
  <crud-component
    :title="s__('ArtifactRegistry|Install')"
    data-testid="install-panel"
    :body-class="block ? '!gl-p-0' : null"
  >
    <template v-if="block" #actions>
      <tool-selector :format="format" :selected="activeTool" @select="selectedTool = $event" />
    </template>

    <snippet-code-block v-if="block" :snippet="block.code" :copy-text="block.copyText" />

    <p v-else class="gl-mb-0 gl-text-subtle" data-testid="install-unavailable">
      {{
        s__(
          'ArtifactRegistry|Install instructions are unavailable because the package could not be loaded.',
        )
      }}
    </p>

    <template v-if="help" #footer>
      <p class="gl-mb-0 gl-text-sm gl-text-subtle">
        <gl-sprintf :message="help.text">
          <template #link="{ content }">
            <gl-link :href="help.path">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </p>
    </template>
  </crud-component>
</template>
