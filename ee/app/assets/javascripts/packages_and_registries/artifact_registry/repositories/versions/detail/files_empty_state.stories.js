import { REPOSITORY_FORMAT_MAVEN, REPOSITORY_FORMAT_NPM } from '../../../constants';
import FilesEmptyState from './files_empty_state.vue';

export default {
  component: FilesEmptyState,
  title: 'ee/artifact_registry/repositories/versions/detail/files_empty_state',
};

const Template =
  ({ format, versionString = '3.2.1' }) =>
  () => ({
    components: { FilesEmptyState },
    data() {
      return { format, versionString };
    },
    template: '<files-empty-state :format="format" :version-string="versionString" />',
  });

export const Maven = Template({ format: REPOSITORY_FORMAT_MAVEN });

export const Npm = Template({ format: REPOSITORY_FORMAT_NPM });
