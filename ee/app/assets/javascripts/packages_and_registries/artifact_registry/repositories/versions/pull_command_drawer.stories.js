import { CLIENT_BASE_URL, SLUG } from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import { mockArtifacts } from '../../graphql/mock_artifacts';
import PullCommandDrawer from './pull_command_drawer.vue';

const REPOSITORY_NAME = 'my-repository';

const VERSION = '3.2.1';

const DIGEST = `sha256:${'1'.repeat(64)}`;

// The artifact the app's own generator holds first for this repository, so the coordinates the
// command carries are the ones a browser renders.
const artifactFor = (format) => mockArtifacts(REPOSITORY_NAME, format)[0];

export default {
  component: PullCommandDrawer,
  title: 'ee/artifact_registry/repositories/versions/pull_command_drawer',
};

const Template =
  (format, row = { version: VERSION }) =>
  () => ({
    components: { PullCommandDrawer },
    provide: { slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
    data() {
      return { format, artifact: artifactFor(format), row, open: false };
    },
    template: `
    <div>
      <button id="reopen" @click="open = true">View pull command</button>
      <pull-command-drawer
        :format="format"
        :artifact="artifact"
        name="${REPOSITORY_NAME}"
        :version="row.version"
        :digest="row.digest"
        :tags="row.tags"
        :open="open"
        @close="open = false"
      />
    </div>
  `,
  });

export const Maven = Template('MAVEN');

export const Npm = Template('NPM', { version: VERSION, tags: ['latest', 'stable'] });

export const Docker = Template('DOCKER', { digest: DIGEST });
