import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlButton } from '@gitlab/ui';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import BlobControlsLockButton from 'ee_component/repository/components/header_area/blob_controls_lock_button.vue';
import LockButton from 'ee_component/repository/components/header_area/lock_button.vue';
import projectInfoQuery from 'ee_else_ce/repository/queries/project_info.query.graphql';
import { getProjectMockWithOverrides } from 'ee_jest/repository/mock_data';

Vue.use(VueApollo);

describe('BlobControlsLockButton component', () => {
  let wrapper;
  let fakeApollo;

  const projectInfoResolverMock = jest.fn();

  const createPathLockNode = (path, id = 'gid://gitlab/PathLock/2') => ({
    __typename: 'PathLock',
    id,
    path,
    createdAt: '2026-07-13T00:00:00Z',
    user: {
      id: 'gid://gitlab/User/1',
      username: 'root',
      name: 'Administrator',
      avatarUrl: 'https://www.gravatar.com/avatar/root?s=80',
      webPath: '/root',
      __typename: 'UserCore',
    },
    userPermissions: {
      destroyPathLock: true,
    },
  });

  const createComponent = async ({ provide = {}, pathLockNodes } = {}) => {
    projectInfoResolverMock.mockResolvedValue({
      data: {
        project: getProjectMockWithOverrides({
          pathLockNodesOverride: pathLockNodes ?? [],
        }),
      },
    });

    fakeApollo = createMockApollo([[projectInfoQuery, projectInfoResolverMock]]);

    wrapper = shallowMountExtended(BlobControlsLockButton, {
      apolloProvider: fakeApollo,
      provide: {
        glFeatures: { repositoryLockInformation: true },
        glLicensedFeatures: { fileLocks: true },
        currentRef: 'main',
        ...provide,
      },
      propsData: {
        projectPath: 'some/project',
        path: 'some/file.js',
      },
      stubs: {
        GlAlert,
        GlButton,
        LockButton: stubComponent(LockButton, {
          template: '<div><slot name="disclosure-alert"></slot><slot name="footer"></slot></div>',
        }),
      },
    });

    await waitForPromises();
  };

  const findLockButton = () => wrapper.findComponent(LockButton);
  const findRelatedLockAlert = () => wrapper.find('[data-testid="related-lock-alert"]');
  const findViewLockedPathButton = () => wrapper.find('[data-testid="view-locked-path-button"]');

  afterEach(() => {
    fakeApollo = null;
    projectInfoResolverMock.mockReset();
  });

  it('renders the lock button when the feature flag and licensed feature are enabled', async () => {
    await createComponent();

    expect(findLockButton().exists()).toBe(true);
    expect(findLockButton().props()).toMatchObject({
      projectPath: 'some/project',
      path: 'some/file.js',
    });
  });

  it('does not render the lock button when `repositoryLockInformation` feature flag is disabled', async () => {
    await createComponent({
      provide: { glFeatures: { repositoryLockInformation: false } },
    });

    expect(findLockButton().exists()).toBe(false);
    expect(projectInfoResolverMock).not.toHaveBeenCalled();
  });

  it('does not render the lock button when `fileLocks` licensed feature is not available', async () => {
    await createComponent({
      provide: { glLicensedFeatures: { fileLocks: false } },
    });

    expect(findLockButton().exists()).toBe(false);
    expect(projectInfoResolverMock).not.toHaveBeenCalled();
  });

  it('passes the default lock state to the lock button when the file is not locked', async () => {
    await createComponent();

    expect(findLockButton().props()).toMatchObject({
      isLocked: false,
      lockUser: null,
      lockedAt: null,
      canDestroyLock: false,
      canCreateLock: true,
    });
  });

  it('passes the lock state to the lock button when the current file is locked', async () => {
    await createComponent({
      pathLockNodes: [createPathLockNode('some/file.js')],
    });

    expect(findLockButton().props()).toMatchObject({
      isLocked: true,
      lockUser: expect.objectContaining({ username: 'root' }),
      lockedAt: '2026-07-13T00:00:00Z',
      canDestroyLock: true,
      canCreateLock: true,
    });
  });

  it('passes the default lock state to the lock button when a different file is locked', async () => {
    await createComponent({
      pathLockNodes: [createPathLockNode('some/other_file.js')],
    });

    expect(findLockButton().props()).toMatchObject({
      isLocked: false,
      lockUser: null,
      lockedAt: null,
      canDestroyLock: false,
    });
    expect(findRelatedLockAlert().exists()).toBe(false);
    expect(findViewLockedPathButton().exists()).toBe(false);
  });

  describe('when a parent directory is locked', () => {
    it('shows the locked state without unlock permission and explains it in an alert', async () => {
      await createComponent({
        pathLockNodes: [createPathLockNode('some')],
      });

      expect(findLockButton().props()).toMatchObject({
        isLocked: true,
        lockUser: expect.objectContaining({ username: 'root' }),
        lockedAt: '2026-07-13T00:00:00Z',
        canDestroyLock: false,
      });
      expect(findRelatedLockAlert().text()).toBe(
        'The parent directory "some" is locked. To unlock this file, unlock "some".',
      );
    });

    it('renders a footer button linking to the locked directory', async () => {
      await createComponent({
        pathLockNodes: [createPathLockNode('some')],
      });

      expect(findViewLockedPathButton().text()).toBe('View lock');
      expect(findViewLockedPathButton().attributes('href')).toBe('/some/project/-/tree/main/some');
    });

    it('ignores a lock on a directory that only shares a path prefix', async () => {
      await createComponent({
        pathLockNodes: [createPathLockNode('some/fi')],
      });

      expect(findLockButton().props('isLocked')).toBe(false);
      expect(findRelatedLockAlert().exists()).toBe(false);
    });

    it('prefers the exact file lock over the parent directory lock', async () => {
      await createComponent({
        pathLockNodes: [
          createPathLockNode('some', 'gid://gitlab/PathLock/3'),
          createPathLockNode('some/file.js'),
        ],
      });

      expect(findLockButton().props()).toMatchObject({
        isLocked: true,
        canDestroyLock: true,
      });
      expect(findRelatedLockAlert().exists()).toBe(false);
      expect(findViewLockedPathButton().exists()).toBe(false);
    });
  });
});
