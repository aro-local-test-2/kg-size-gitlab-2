import createMockApollo from 'helpers/mock_apollo_helper';
import {
  ORGANIZATION_GID,
  REGISTRY_ID,
  mockArtifactRegistryResponse,
  mockCreateRepositoryResponse,
  mockNamespacePermissions,
} from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import {
  REPOSITORY_NEW_HOSTED_ROUTE_NAME,
  REPOSITORY_NEW_REMOTE_ROUTE_NAME,
} from '../../constants';
import createRepositoryMutation from '../../graphql/mutations/create_repository.mutation.graphql';
import getRegistryPermissionsQuery from '../../graphql/queries/get_registry_permissions.query.graphql';
import { createRouter } from '../../router';
import RepositoriesCreateForm from './repositories_create_form.vue';

const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

const createHandler = () => Promise.resolve(mockCreateRepositoryResponse());

const permissionsHandler = () =>
  Promise.resolve(
    mockArtifactRegistryResponse({
      __typename: 'ArtifactRegistry',
      id: REGISTRY_ID,
      userPermissions: mockNamespacePermissions(),
    }),
  );

export default {
  component: RepositoriesCreateForm,
  title: 'ee/artifact_registry/repositories/create/repositories_create_form',
};

const Template = (routeName) => () => {
  // The page reads the kind it creates from the route, so the story navigates to that
  // kind's create route before rendering.
  const router = createRouter(BASE_PATH);
  router.push({ name: routeName });

  return {
    components: { RepositoriesCreateForm },
    router,
    apolloProvider: createMockApollo([
      [getRegistryPermissionsQuery, permissionsHandler],
      [createRepositoryMutation, createHandler],
    ]),
    provide: { organizationGid: ORGANIZATION_GID },
    template: '<repositories-create-form />',
  };
};

export const Hosted = Template(REPOSITORY_NEW_HOSTED_ROUTE_NAME);

export const Remote = Template(REPOSITORY_NEW_REMOTE_ROUTE_NAME);
