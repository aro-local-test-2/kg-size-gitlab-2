import {
  REPOSITORY_FORMAT_MAVEN,
  REPOSITORY_FORMAT_NPM,
  TYPENAME_ARTIFACT_REGISTRY_MAVEN_VERSION_FILE,
  TYPENAME_ARTIFACT_REGISTRY_NPM_VERSION_FILE,
} from '../../../constants';
import FilesTable from './files_table.vue';

const MAVEN_FILE_NAMES = [
  'core-3.2.1.jar',
  'core-3.2.1.pom',
  'core-3.2.1-sources.jar',
  'core-3.2.1-javadoc.jar',
  'maven-metadata.xml',
];

const NPM_FILE_NAMES = ['design-system-4.2.0.tgz'];

const fileId = (index) => `01937b2e-0000-7000-8000-${String(index).padStart(12, '0')}`;

const FILES = {
  [REPOSITORY_FORMAT_MAVEN]: MAVEN_FILE_NAMES.map((fileName, index) => ({
    __typename: TYPENAME_ARTIFACT_REGISTRY_MAVEN_VERSION_FILE,
    id: fileId(index),
    fileName,
    sizeBytes: String(4096 * (index + 1)),
    createdAt: null,
    md5: index === MAVEN_FILE_NAMES.length - 1 ? null : String(index).repeat(32).slice(0, 32),
    sha1: String(index).repeat(40).slice(0, 40),
    sha256: String(index).repeat(64).slice(0, 64),
    sha512: String(index).repeat(128).slice(0, 128),
  })),
  [REPOSITORY_FORMAT_NPM]: NPM_FILE_NAMES.map((fileName, index) => ({
    __typename: TYPENAME_ARTIFACT_REGISTRY_NPM_VERSION_FILE,
    id: fileId(index),
    fileName,
    sizeBytes: String(524288 * (index + 1)),
    createdAt: '2026-06-10T00:00:00Z',
    sha256: String(index).repeat(64).slice(0, 64),
  })),
};

export default {
  component: FilesTable,
  title: 'ee/artifact_registry/repositories/versions/detail/files_table',
};

const Template =
  ({ format, expanded = false, isLoading = false }) =>
  () => ({
    components: { FilesTable },
    data() {
      return {
        format,
        isLoading,
        files: FILES[format],
      };
    },
    async mounted() {
      if (!expanded) return;

      await this.$nextTick();

      this.$el
        .querySelectorAll('[data-testid="toggle-checksums"]')
        .forEach((toggle) => toggle.click());
    },
    template: '<files-table :files="files" :format="format" :is-loading="isLoading" />',
  });

// Works around bootstrap-vue putting `aria-owns` on an open row, which breaks
// `aria-required-children`. Only the disclosed stories, so the rest still check the rule.
const disclosedA11y = {
  a11y: { config: { rules: [{ id: 'aria-required-children', enabled: false }] } },
};

export const Maven = Template({ format: REPOSITORY_FORMAT_MAVEN });

export const MavenChecksumsDisclosed = Template({
  format: REPOSITORY_FORMAT_MAVEN,
  expanded: true,
});
MavenChecksumsDisclosed.parameters = disclosedA11y;

export const Npm = Template({ format: REPOSITORY_FORMAT_NPM });

export const NpmChecksumsDisclosed = Template({ format: REPOSITORY_FORMAT_NPM, expanded: true });
NpmChecksumsDisclosed.parameters = disclosedA11y;

export const Loading = Template({ format: REPOSITORY_FORMAT_MAVEN, isLoading: true });
