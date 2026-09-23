import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import getGroupProjects from 'ee/security_orchestration/graphql/queries/get_group_projects.query.graphql';
import getOrganizationProjects from 'ee/policy_store/graphql/get_organization_projects.query.graphql';
import BaseItemsDropdown from 'ee/security_orchestration/components/shared/base_items_dropdown.vue';
import BaseProjectsDropdown from 'ee/policy_store/components/editor/base_projects_dropdown.vue';
import ProjectsCountMessage from 'ee/security_orchestration/components/shared/projects_count_message.vue';
import { generateMockProjects } from 'ee_jest/security_orchestration/mocks/mock_data';

describe('BaseProjectsDropdown', () => {
  let wrapper;
  let requestHandlers;

  const GROUP_FULL_PATH = 'gitlab-org';

  const defaultNodes = generateMockProjects([1, 2]);
  const mapIds = (nodes) => nodes.map(({ id }) => id);
  const defaultNodesIds = mapIds(defaultNodes);

  const mapItems = (items) =>
    items.map(({ id, name, fullPath }) => ({ value: id, text: name, fullPath }));

  const defaultPageInfo = {
    __typename: 'PageInfo',
    hasNextPage: false,
    hasPreviousPage: false,
    startCursor: null,
    endCursor: null,
  };

  const mockApolloHandlers = (nodes = defaultNodes, hasNextPage = false, count = 0) => {
    return {
      getGroupProjects: jest.fn().mockResolvedValue({
        data: {
          id: 1,
          group: {
            id: 2,
            projects: {
              ...(count > 0 ? { count } : {}),
              nodes,
              pageInfo: { ...defaultPageInfo, hasNextPage },
            },
          },
        },
      }),
    };
  };

  const createMockApolloProvider = (handlers) => {
    Vue.use(VueApollo);

    requestHandlers = handlers;
    return createMockApollo([[getGroupProjects, requestHandlers.getGroupProjects]]);
  };

  const createComponent = ({
    propsData = {},
    handlers = mockApolloHandlers(),
    stubs = {},
  } = {}) => {
    wrapper = shallowMountExtended(BaseProjectsDropdown, {
      apolloProvider: createMockApolloProvider(handlers),
      propsData: {
        query: getGroupProjects,
        responsePath: 'group.projects',
        pathVariables: { fullPath: GROUP_FULL_PATH },
        ...propsData,
      },
      stubs,
    });
  };

  const findDropdown = () => wrapper.findComponent(BaseItemsDropdown);
  const findFooter = () => wrapper.findComponent(ProjectsCountMessage);

  describe('selection', () => {
    beforeEach(() => {
      createComponent();
    });

    it('should render loading state', () => {
      expect(findDropdown().props('loading')).toBe(true);
      expect(findFooter().exists()).toBe(false);
    });

    it('should load items', async () => {
      await waitForPromises();
      expect(findDropdown().props('loading')).toBe(false);
      expect(findDropdown().props('items')).toEqual(mapItems(defaultNodes));
    });

    it('should select items', async () => {
      const [{ id }] = defaultNodes;

      await waitForPromises();
      findDropdown().vm.$emit('select', [id]);
      expect(wrapper.emitted('select')).toEqual([[[defaultNodes[0]]]]);
    });
  });

  describe('selected items', () => {
    beforeEach(() => {
      createComponent({
        propsData: {
          selected: defaultNodesIds,
        },
      });
    });

    it(`should be possible to preselect projects`, async () => {
      await waitForPromises();
      expect(findDropdown().props('selected')).toEqual(defaultNodesIds);
    });
  });

  describe('selected items that does not exist', () => {
    it('filters selected projects that does not exist', async () => {
      createComponent({
        propsData: {
          selected: ['one', 'two'],
        },
      });

      await waitForPromises();
      findDropdown().vm.$emit('select', [defaultNodesIds[0]]);

      expect(wrapper.emitted('select')).toEqual([[[defaultNodes[0]]]]);
    });
  });

  describe('select single project', () => {
    it('support single selection mode', async () => {
      createComponent({
        propsData: {
          multiple: false,
        },
      });

      await waitForPromises();

      findDropdown().vm.$emit('select', defaultNodesIds[0]);
      expect(wrapper.emitted('select')).toEqual([[defaultNodes[0]]]);
    });

    it('should render single selected project', async () => {
      createComponent({
        propsData: {
          multiple: false,
          selected: defaultNodesIds[0],
        },
      });

      await waitForPromises();

      expect(findDropdown().props('selected')).toEqual(defaultNodesIds[0]);
    });
  });

  describe('when there is more than a page of projects', () => {
    describe('when bottom reached on scrolling', () => {
      describe('projects', () => {
        it('fetches more projects on scroll', async () => {
          createComponent({ handlers: mockApolloHandlers([], true) });
          await waitForPromises();
          findDropdown().vm.$emit('bottom-reached');
          expect(requestHandlers.getGroupProjects).toHaveBeenCalledTimes(2);
        });
      });

      describe('when the fetch query throws an error', () => {
        it('emits an error event', async () => {
          createComponent({
            handlers: {
              getGroupProjects: jest.fn().mockRejectedValue({}),
            },
          });
          await waitForPromises();
          expect(wrapper.emitted('projects-query-error')).toHaveLength(1);
        });
      });
    });

    describe('when fetch query returns group as null', () => {
      it('renders an empty list without emitting an error', async () => {
        createComponent({
          handlers: {
            getGroupProjects: jest.fn().mockResolvedValue({
              data: {
                id: 1,
                group: null,
              },
            }),
          },
        });

        await waitForPromises();

        expect(findDropdown().props('items')).toEqual([]);
        expect(wrapper.emitted('projects-query-error')).toBeUndefined();
      });
    });

    describe('when a query is loading a new page of projects', () => {
      it('should render the loading spinner', async () => {
        createComponent({ handlers: mockApolloHandlers([], true) });
        await waitForPromises();

        findDropdown().vm.$emit('bottom-reached');
        await nextTick();

        expect(findDropdown().props('loading')).toBe(true);
      });
    });
  });

  describe('validation', () => {
    it('renders default dropdown when validation passes', () => {
      createComponent({
        propsData: {
          state: true,
        },
      });

      expect(findDropdown().props('variant')).toEqual('default');
      expect(findDropdown().props('category')).toEqual('primary');
    });

    it('renders danger dropdown when validation passes', () => {
      createComponent();

      expect(findDropdown().props('variant')).toEqual('danger');
      expect(findDropdown().props('category')).toEqual('secondary');
    });
  });

  describe('select all', () => {
    describe('items', () => {
      it(`selects all projects`, async () => {
        createComponent();
        await waitForPromises();

        findDropdown().vm.$emit('select-all', defaultNodesIds);

        expect(wrapper.emitted('select')).toEqual([[defaultNodes]]);
      });

      it('resets all projects', async () => {
        createComponent();

        await waitForPromises();

        findDropdown().vm.$emit('reset');

        expect(wrapper.emitted('select')).toEqual([[[]]]);
      });
    });
  });

  describe('selection after search', () => {
    describe('projects', () => {
      it('should add projects to existing selection after search', async () => {
        const moreNodes = generateMockProjects([1, 2, 3, 44, 444, 4444]);
        createComponent({
          propsData: {
            selected: defaultNodesIds,
          },
          handlers: mockApolloHandlers(moreNodes),
          stubs: {
            BaseItemsDropdown,
            GlCollapsibleListbox,
          },
        });

        await waitForPromises();

        expect(findDropdown().props('selected')).toEqual(defaultNodesIds);

        findDropdown().vm.$emit('search', '4');
        await waitForPromises();

        expect(requestHandlers.getGroupProjects).toHaveBeenCalledWith({
          fullPath: GROUP_FULL_PATH,
          projectIds: null,
          search: '4',
          withCount: false,
        });

        const filteredItems = findDropdown().props('items');
        expect(filteredItems.every((item) => item.text.includes('4'))).toBe(true);

        await waitForPromises();
        await wrapper
          .findComponentByTestId(`listbox-item-${moreNodes[3].id}`)
          .vm.$emit('select', true);

        expect(wrapper.emitted('select')).toEqual([[[...defaultNodes, moreNodes[3]]]]);
      });
    });

    it('should filter projects by fullPath in search', async () => {
      createComponent();
      await waitForPromises();

      findDropdown().vm.$emit('search', 'project-1-full-path');
      await waitForPromises();

      expect(findDropdown().props('items')).toEqual(mapItems([defaultNodes[0]]));
      expect(requestHandlers.getGroupProjects).toHaveBeenCalledWith({
        projectIds: null,
        search: 'project-1-full-path',
        fullPath: GROUP_FULL_PATH,
        withCount: false,
      });
    });
  });

  describe('missing projects', () => {
    const newProjects = generateMockProjects([3, 4]);
    const newProjectsIds = mapIds(newProjects);

    it.each`
      multiple | selected             | projectIds
      ${true}  | ${newProjectsIds}    | ${newProjectsIds}
      ${false} | ${newProjectsIds[0]} | ${[newProjectsIds[0]]}
    `(
      'loads projects if they were selected but missing from first loaded page',
      async ({ multiple, selected, projectIds }) => {
        createComponent({
          propsData: {
            multiple,
            selected,
          },
        });
        await waitForPromises();

        expect(requestHandlers.getGroupProjects).toHaveBeenNthCalledWith(
          2,
          expect.objectContaining({
            projectIds,
          }),
        );
      },
    );
  });

  describe('project count', () => {
    const nodes = generateMockProjects(Array.from({ length: 101 }).map((_, i) => i));

    describe('default rendering', () => {
      beforeEach(async () => {
        createComponent({
          propsData: {
            withProjectCount: true,
          },
          handlers: mockApolloHandlers(nodes, true, 150),
        });
        await waitForPromises();
      });

      it('renders footer with project information', () => {
        expect(findFooter().exists()).toBe(true);
        expect(findFooter().props('count')).toBe(101);
        expect(findFooter().props('totalCount')).toBe(150);
        expect(findFooter().props('infoText')).toBe('projects');
        expect(findFooter().props('showInfoIcon')).toBe(true);
      });

      it('queries projects with project count enabled', () => {
        expect(requestHandlers.getGroupProjects).toHaveBeenCalledWith({
          fullPath: GROUP_FULL_PATH,
          projectIds: null,
          withCount: true,
        });
      });
    });

    describe('select all projects', () => {
      it('loads all projects when select all is clicked', async () => {
        createComponent({
          propsData: {
            withProjectCount: true,
          },
          stubs: {
            GlSprintf,
          },
          handlers: mockApolloHandlers(nodes, false, 150),
        });

        await waitForPromises();

        const allProjectIds = nodes.map(({ id }) => id);
        await findDropdown().vm.$emit('select-all', allProjectIds);

        expect(requestHandlers.getGroupProjects).toHaveBeenNthCalledWith(1, {
          fullPath: GROUP_FULL_PATH,
          projectIds: null,
          withCount: true,
        });

        expect(requestHandlers.getGroupProjects).toHaveBeenNthCalledWith(2, {
          fullPath: GROUP_FULL_PATH,
          projectIds: null,
          search: '',
          withCount: true,
        });

        expect(wrapper.emitted('select')).toBeDefined();
        expect(wrapper.emitted('select')[0][0]).toHaveLength(nodes.length);
      });
    });

    describe('search', () => {
      it('does not query backend on search when all projects were loaded', async () => {
        createComponent({
          propsData: {
            withProjectCount: true,
          },
          stubs: {
            GlSprintf,
          },
          handlers: mockApolloHandlers(nodes, false, 101),
        });

        await waitForPromises();

        expect(requestHandlers.getGroupProjects).toHaveBeenCalledTimes(1);

        findDropdown().vm.$emit('search', 'project-1-full-path');

        expect(requestHandlers.getGroupProjects).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('with an organization source', () => {
    const ORGANIZATION_GID = 'gid://gitlab/Organizations::Organization/1';

    // The organization query selects no `group` field, so its nodes carry
    // fewer keys than generateMockProjects produces.
    const organizationProjectNode = (id) => ({
      id: `gid://gitlab/Project/${id}`,
      name: `${id}`,
      fullPath: `org-group/project-${id}`,
      repository: { rootRef: 'main', __typename: 'Repository' },
      __typename: 'Project',
    });

    const organizationNodes = [organizationProjectNode(1), organizationProjectNode(2)];

    const organizationResponse = (nodes) => ({
      data: {
        organization: {
          id: ORGANIZATION_GID,
          projects: {
            nodes,
            pageInfo: defaultPageInfo,
            __typename: 'ProjectConnection',
          },
          __typename: 'Organization',
        },
      },
    });

    const createOrganizationComponent = ({
      propsData = {},
      handler = jest.fn().mockResolvedValue(organizationResponse(organizationNodes)),
    } = {}) => {
      Vue.use(VueApollo);
      requestHandlers = { getOrganizationProjects: handler };

      wrapper = shallowMountExtended(BaseProjectsDropdown, {
        apolloProvider: createMockApollo([[getOrganizationProjects, handler]]),
        propsData: {
          query: getOrganizationProjects,
          responsePath: 'organization.projects',
          pathVariables: { id: ORGANIZATION_GID },
          ...propsData,
        },
      });
    };

    it('reads the projects from the organization response path', async () => {
      createOrganizationComponent();
      await waitForPromises();

      expect(requestHandlers.getOrganizationProjects).toHaveBeenCalledWith(
        expect.objectContaining({ id: ORGANIZATION_GID }),
      );
      expect(findDropdown().props('items')).toEqual(mapItems(organizationNodes));
    });

    it('refetches with the search term alongside the organization id', async () => {
      createOrganizationComponent();
      await waitForPromises();

      findDropdown().vm.$emit('search', 'web');
      jest.runAllTimers();
      await waitForPromises();

      expect(requestHandlers.getOrganizationProjects).toHaveBeenLastCalledWith(
        expect.objectContaining({ id: ORGANIZATION_GID, search: 'web' }),
      );
    });

    it('emits the selected project objects', async () => {
      createOrganizationComponent();
      await waitForPromises();

      findDropdown().vm.$emit('select', [organizationNodes[0].id]);

      expect(wrapper.emitted('select')).toEqual([[[organizationNodes[0]]]]);
    });

    it('backfills selected projects that the first page did not include', async () => {
      const missing = [organizationProjectNode(99)];

      createOrganizationComponent({
        propsData: { selected: mapIds(missing) },
        handler: jest
          .fn()
          .mockResolvedValueOnce(organizationResponse(organizationNodes))
          .mockResolvedValue(organizationResponse(missing)),
      });
      await waitForPromises();

      expect(requestHandlers.getOrganizationProjects).toHaveBeenCalledWith(
        expect.objectContaining({ projectIds: mapIds(missing) }),
      );
      expect(findDropdown().props('selected')).toEqual(mapIds(missing));
    });

    it('adds nothing and stays quiet when the backfill returns a null organization', async () => {
      createOrganizationComponent({
        propsData: { selected: ['gid://gitlab/Project/99'] },
        handler: jest
          .fn()
          .mockResolvedValueOnce(organizationResponse(organizationNodes))
          .mockResolvedValue({ data: { organization: null } }),
      });
      await waitForPromises();

      expect(findDropdown().props('items')).toEqual(mapItems(organizationNodes));
      expect(wrapper.emitted('projects-query-error')).toBeUndefined();
    });

    it('emits an error event when the query fails', async () => {
      createOrganizationComponent({ handler: jest.fn().mockRejectedValue(new Error('boom')) });
      await waitForPromises();

      expect(wrapper.emitted('projects-query-error')).toHaveLength(1);
    });
  });
});
