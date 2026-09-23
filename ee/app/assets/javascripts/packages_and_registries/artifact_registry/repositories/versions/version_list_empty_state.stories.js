import { createRouter } from '../../router';
import VersionListEmptyState from './version_list_empty_state.vue';

const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

export default {
  component: VersionListEmptyState,
  title: 'ee/artifact_registry/repositories/versions/version_list_empty_state',
};

const Template = (format) => () => ({
  components: { VersionListEmptyState },
  router: createRouter(BASE_PATH),
  data() {
    return { format };
  },
  template: '<version-list-empty-state name="my-repository" :format="format" />',
});

export const Maven = Template('MAVEN');

export const Npm = Template('NPM');

export const Docker = Template('DOCKER');

export const Oci = Template('OCI');
