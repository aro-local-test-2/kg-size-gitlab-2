import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import deleteArtifactMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_artifact.mutation.graphql';
import ArtifactActions from 'ee/packages_and_registries/artifact_registry/repositories/versions/artifact_actions.vue';
import DeleteConfirmationModal from 'ee/packages_and_registries/artifact_registry/repositories/components/delete_confirmation_modal.vue';
import { createRouter } from 'ee/packages_and_registries/artifact_registry/router';
import {
  BASE_PATH,
  mockDeleteArtifactResponse,
  mockDeniedRepositoryPermissions,
  mockRepository,
  mockRepositoryPermissions,
} from '../../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

const REPOSITORY_NAME = mockRepository.name;

const IMAGE = { id: 'img-1', name: 'payment-service' };
const MAVEN_PACKAGE = { id: 'pkg-1', groupId: 'com.company.payment', artifactId: 'core' };
const NPM_PACKAGE = { id: 'pkg-2', name: '@acme/ui-components' };

const ARTIFACT_FOR = {
  MAVEN: MAVEN_PACKAGE,
  NPM: NPM_PACKAGE,
  DOCKER: IMAGE,
  OCI: IMAGE,
};

describe('ArtifactRegistryArtifactActions', () => {
  let wrapper;
  let router;
  let deleteHandler;

  const mockToast = { show: jest.fn() };

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findItems = () => wrapper.findAllComponents(GlDisclosureDropdownItem);
  const findDeleteItem = () => wrapper.findComponentByTestId('delete-artifact');
  const findModal = () => wrapper.findComponent(DeleteConfirmationModal);

  const createComponent = async ({
    format = 'MAVEN',
    artifact = ARTIFACT_FOR[format],
    permissions = mockRepositoryPermissions(),
  } = {}) => {
    deleteHandler = jest.fn().mockResolvedValue(mockDeleteArtifactResponse());

    router = createRouter(BASE_PATH);
    await router.push(`/${REPOSITORY_NAME}/${artifact.id}`);

    wrapper = shallowMountExtended(ArtifactActions, {
      router,
      apolloProvider: createMockApollo([[deleteArtifactMutation, deleteHandler]]),
      propsData: { artifact, format, name: REPOSITORY_NAME, permissions },
      mocks: { $toast: mockToast },
    });
  };

  const openModal = async () => {
    findDeleteItem().props('item').action();
    await nextTick();
  };

  const confirmDeletion = async (artifact = findModal().props('target')) => {
    findModal().vm.$emit('confirm', artifact);
    await waitForPromises();
  };

  describe('the menu', () => {
    beforeEach(() => createComponent());

    it('renders the toggle as an icon-only tertiary button', () => {
      expect(findDropdown().props()).toMatchObject({
        icon: 'ellipsis_v',
        textSrOnly: true,
        category: 'tertiary',
        noCaret: true,
        placement: 'bottom-end',
        loading: false,
      });
    });

    it('offers the delete action alone', () => {
      expect(findItems()).toHaveLength(1);
      expect(findDeleteItem().exists()).toBe(true);
    });
  });

  it.each`
    format      | displayName
    ${'MAVEN'}  | ${'com.company.payment:core'}
    ${'NPM'}    | ${'@acme/ui-components'}
    ${'DOCKER'} | ${'payment-service'}
  `(
    'names the $format artifact in the toggle, which renders as an icon alone',
    async ({ format, displayName }) => {
      await createComponent({ format });

      expect(findDropdown().props('toggleText')).toBe(`More actions for ${displayName}`);
    },
  );

  it.each`
    format      | text                | title
    ${'MAVEN'}  | ${'Delete package'} | ${'Delete package?'}
    ${'NPM'}    | ${'Delete package'} | ${'Delete package?'}
    ${'DOCKER'} | ${'Delete image'}   | ${'Delete image?'}
    ${'OCI'}    | ${'Delete image'}   | ${'Delete image?'}
  `(
    'marks the destructive $format action as "$text" and titles its confirmation "$title"',
    async ({ format, text, title }) => {
      await createComponent({ format });

      expect(findDeleteItem().props('item')).toMatchObject({ text, variant: 'danger' });
      expect(findModal().props()).toMatchObject({ title, actionText: text });
    },
  );

  describe('the delete modal', () => {
    beforeEach(() => createComponent());

    it('hands the modal the copy for the format', () => {
      expect(findModal().props()).toMatchObject({
        title: 'Delete package?',
        body: 'This action permanently deletes package %{name} and all of its versions. This action cannot be undone.',
        actionText: 'Delete package',
      });
    });

    it('starts closed', () => {
      expect(findModal().props('target')).toBeNull();
    });

    it('opens on the artifact when the delete action is chosen', async () => {
      await openModal();

      expect(findModal().props('target')).toStrictEqual(MAVEN_PACKAGE);
    });

    it('closes again when the modal reports it was dismissed', async () => {
      await openModal();

      findModal().vm.$emit('change', null);
      await nextTick();

      expect(findModal().props('target')).toBeNull();
    });

    it('sends nothing until the modal confirms', async () => {
      await openModal();

      expect(deleteHandler).not.toHaveBeenCalled();
    });
  });

  describe('confirming the deletion', () => {
    beforeEach(async () => {
      await createComponent();
      await openModal();
      await confirmDeletion();
    });

    it('deletes the artifact the page renders, in the repository the route names', () => {
      expect(deleteHandler).toHaveBeenCalledTimes(1);
      expect(deleteHandler).toHaveBeenCalledWith({
        input: { name: REPOSITORY_NAME, id: MAVEN_PACKAGE.id },
      });
    });

    it('reports the deletion as scheduled through the toast', () => {
      expect(mockToast.show).toHaveBeenCalledWith('Package successfully scheduled for deletion.');
      expect(createAlert).not.toHaveBeenCalled();
    });

    it('returns to the repository the artifact belonged to', () => {
      expect(router.currentRoute.name).toBe('repository_detail');
      expect(router.currentRoute.params).toEqual({ id: REPOSITORY_NAME });
    });
  });

  it('reports an image deletion as an image', async () => {
    await createComponent({ format: 'DOCKER' });

    await openModal();
    await confirmDeletion();

    expect(mockToast.show).toHaveBeenCalledWith('Image successfully scheduled for deletion.');
  });

  describe('while a deletion is in flight', () => {
    beforeEach(async () => {
      await createComponent();
      deleteHandler.mockReturnValue(new Promise(() => {}));

      await openModal();
      await confirmDeletion();
    });

    it('marks the menu as loading', () => {
      expect(findDropdown().props('loading')).toBe(true);
    });

    it('sends one request for a deletion confirmed again', async () => {
      await openModal();
      await confirmDeletion();

      expect(deleteHandler).toHaveBeenCalledTimes(1);
    });
  });

  describe('when the service rejects the deletion', () => {
    beforeEach(async () => {
      await createComponent();
      deleteHandler.mockResolvedValue(
        mockDeleteArtifactResponse({ errors: ['Artifact not found.'] }),
      );

      await openModal();
      await confirmDeletion();
    });

    it('surfaces the error and shows no success toast', () => {
      expect(createAlert).toHaveBeenCalledWith({ message: 'Artifact not found.' });
      expect(mockToast.show).not.toHaveBeenCalled();
    });

    it('stays on the page', () => {
      expect(router.currentRoute.name).toBe('artifact_versions');
    });
  });

  describe('when the request fails', () => {
    const error = new Error('Artifact Registry is down');

    beforeEach(async () => {
      await createComponent();
      deleteHandler.mockRejectedValue(error);

      await openModal();
      await confirmDeletion();
    });

    it('reports the failure as a page-level alert and shows no success toast', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Something went wrong. Please try again.',
        error,
        captureError: true,
      });
      expect(mockToast.show).not.toHaveBeenCalled();
    });

    it('stays on the page', () => {
      expect(router.currentRoute.name).toBe('artifact_versions');
    });
  });

  describe('the delete verdict', () => {
    it('offers the delete action when it allows', async () => {
      await createComponent({ permissions: mockRepositoryPermissions() });

      expect(findDeleteItem().exists()).toBe(true);
    });

    describe('when it denies', () => {
      beforeEach(() => createComponent({ permissions: mockDeniedRepositoryPermissions() }));

      it('renders neither the delete action nor the toggle', () => {
        expect(findDeleteItem().exists()).toBe(false);
        expect(findDropdown().exists()).toBe(false);
      });

      it('keeps the confirmation modal mounted and closed', () => {
        expect(findModal().exists()).toBe(true);
        expect(findModal().props('target')).toBeNull();
      });
    });

    describe('when the read carrying it has not answered', () => {
      beforeEach(() => createComponent({ permissions: null }));

      it('renders no toggle, so nothing is offered optimistically', () => {
        expect(findDropdown().exists()).toBe(false);
      });
    });
  });
});
