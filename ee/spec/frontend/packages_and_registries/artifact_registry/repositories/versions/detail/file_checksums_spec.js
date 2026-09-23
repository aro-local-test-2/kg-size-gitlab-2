import mavenFilesFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version_files.query.graphql.json';
import npmFilesFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_version_files.npm.query.graphql.json';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FileChecksums from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/file_checksums.vue';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import DetailsRow from '~/vue_shared/components/registry/details_row.vue';

const fileNodes = (fixture) =>
  fixture.data.organization.artifactRegistryRepository.version.files.nodes;

const mavenFiles = fileNodes(mavenFilesFixture);
const npmFiles = fileNodes(npmFilesFixture);

const [mavenFile] = mavenFiles;
const unchecksummedFile = mavenFiles.find(({ md5 }) => md5 === null);
const [npmFile] = npmFiles;

describe('ArtifactRegistryFileChecksums', () => {
  let wrapper;

  const createComponent = ({ file = mavenFile, format = 'MAVEN' } = {}) => {
    wrapper = shallowMountExtended(FileChecksums, { propsData: { file, format } });
  };

  const findRows = () => wrapper.findAllComponents(DetailsRow);
  const findLabels = () =>
    wrapper.findAllByTestId('checksum-label').wrappers.map((label) => label.text());
  const findValues = () =>
    wrapper.findAllByTestId('checksum-value').wrappers.map((value) => value.text());
  const findCopyButtons = () => wrapper.findAllComponents(ClipboardButton);

  describe('a Maven file', () => {
    beforeEach(() => createComponent());

    it('discloses all four checksums, weakest first', () => {
      expect(findLabels()).toEqual(['MD5:', 'SHA-1:', 'SHA-256:', 'SHA-512:']);
    });

    it('renders each checksum in full rather than truncated', () => {
      expect(findValues()).toEqual([
        mavenFile.md5,
        mavenFile.sha1,
        mavenFile.sha256,
        mavenFile.sha512,
      ]);
    });

    it('names the file in every copy action, so two open rows stay distinguishable', () => {
      expect(findCopyButtons().wrappers.map((button) => button.props('title'))).toEqual([
        `Copy MD5 for ${mavenFile.fileName}`,
        `Copy SHA-1 for ${mavenFile.fileName}`,
        `Copy SHA-256 for ${mavenFile.fileName}`,
        `Copy SHA-512 for ${mavenFile.fileName}`,
      ]);
    });

    it('gives each button its own checksum to copy, not the first one four times', () => {
      expect(findCopyButtons().wrappers.map((button) => button.props('text'))).toEqual([
        mavenFile.md5,
        mavenFile.sha1,
        mavenFile.sha256,
        mavenFile.sha512,
      ]);
    });

    it('separates every row but the last, so the disclosure reads as one panel', () => {
      expect(findRows().wrappers.map((row) => row.props('dashed'))).toEqual([
        true,
        true,
        true,
        false,
      ]);
    });
  });

  describe('a Maven file the deploy stored no MD5 for', () => {
    beforeEach(() => createComponent({ file: unchecksummedFile }));

    it('drops the MD5 row rather than rendering it blank', () => {
      expect(findLabels()).toEqual(['SHA-1:', 'SHA-256:', 'SHA-512:']);
    });
  });

  describe('a file carrying no checksum at all', () => {
    beforeEach(() =>
      createComponent({
        file: { ...mavenFile, md5: null, sha1: null, sha256: null, sha512: null },
      }),
    );

    it('renders nothing, rather than an empty panel', () => {
      expect(findRows()).toHaveLength(0);
      expect(wrapper.find('div').exists()).toBe(false);
    });
  });

  describe('an npm file', () => {
    beforeEach(() => createComponent({ file: npmFile, format: 'NPM' }));

    it('discloses only the checksum the registry stores for the format', () => {
      expect(findLabels()).toEqual(['SHA-256:']);
      expect(findValues()).toEqual([npmFile.sha256]);
    });

    it('still gives it a copy action', () => {
      expect(findCopyButtons()).toHaveLength(1);
      expect(findCopyButtons().at(0).props('title')).toBe(`Copy SHA-256 for ${npmFile.fileName}`);
    });
  });
});
