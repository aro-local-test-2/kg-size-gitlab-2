import createMockApollo from 'helpers/mock_apollo_helper';
import {
  ORGANIZATION_GID,
  mockEmptyUpstreamRepositoryCandidatePage,
  mockUpstreamRepositoryCandidatePages,
  mockUpstreamRepositoryCandidatesResponse,
  mockUpstreamSources,
} from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import getUpstreamRepositoryCandidatesQuery from '../../graphql/queries/get_upstream_repository_candidates.query.graphql';
import { createRouter } from '../../router';
import RepositoryForm from './repository_form.vue';

const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

const NEW_REPOSITORY = {
  format: 'DOCKER',
  name: '',
  description: '',
  visibility: 'PRIVATE',
};

export default {
  component: RepositoryForm,
  title: 'ee/artifact_registry/repositories/components/repository_form',
};

const candidatesHandler = (pages) => {
  let index = 0;

  return () => {
    const page = pages[Math.min(index, pages.length - 1)];
    index += 1;

    return Promise.resolve(mockUpstreamRepositoryCandidatesResponse(page));
  };
};

const createTemplate =
  (pages) =>
  (_, { argTypes }) => ({
    components: { RepositoryForm },
    props: Object.keys(argTypes),
    router: createRouter(BASE_PATH),
    apolloProvider: createMockApollo([
      [getUpstreamRepositoryCandidatesQuery, candidatesHandler(pages)],
    ]),
    provide: { organizationGid: ORGANIZATION_GID },
    template: '<repository-form v-bind="$props" />',
  });

const Template = createTemplate(mockUpstreamRepositoryCandidatePages);

export const Default = Template.bind({});
Default.args = {
  repository: NEW_REPOSITORY,
  submitText: 'Create repository',
};

// The edit flow's shape: the name is shown but cannot be changed, and the format is
// not offered at all.
export const Edit = Template.bind({});
Edit.args = {
  repository: {
    format: 'MAVEN',
    name: 'my-repository',
    description: 'A hosted Maven repository',
    visibility: 'PRIVATE',
  },
  submitText: 'Save changes',
  nameReadonly: true,
  showFormat: false,
};

export const Submitting = Template.bind({});
Submitting.args = {
  ...Default.args,
  submitting: true,
};

export const WithErrors = Template.bind({});
WithErrors.args = {
  ...Default.args,
  errorMessages: ['Name has already been taken.', 'Format is not supported.'],
};

const VIRTUAL_CREATE_ARGS = {
  repository: { ...NEW_REPOSITORY, format: 'MAVEN' },
  submitText: 'Create repository',
  kind: 'VIRTUAL',
  createMode: true,
};

export const VirtualWithoutUpstreamRepositories = Template.bind({});
VirtualWithoutUpstreamRepositories.args = VIRTUAL_CREATE_ARGS;

export const VirtualWithUpstreamRepositories = Template.bind({});
VirtualWithUpstreamRepositories.args = {
  ...VIRTUAL_CREATE_ARGS,
  upstreamRepositories: mockUpstreamSources,
};

export const VirtualAtUpstreamRepositoriesCap = Template.bind({});
VirtualAtUpstreamRepositoriesCap.args = {
  ...VIRTUAL_CREATE_ARGS,
  upstreamRepositories: Array.from({ length: 20 }, (_, index) => ({
    id: `cap-${index + 1}`,
    name: `platform-libs-${index + 1}`,
    kind: 'HOSTED',
    url: null,
    sizeBytes: null,
  })),
};

export const VirtualWithNoAttachableRepositories = createTemplate([
  mockEmptyUpstreamRepositoryCandidatePage,
]).bind({});
VirtualWithNoAttachableRepositories.args = VIRTUAL_CREATE_ARGS;
