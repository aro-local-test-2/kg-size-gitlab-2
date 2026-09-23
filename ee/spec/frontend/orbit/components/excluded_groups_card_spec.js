import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import ExcludedGroupsCard from 'ee/orbit/components/excluded_groups_card.vue';
import excludedNamespacesQuery from 'ee/orbit/graphql/queries/excluded_namespaces.query.graphql';
import excludedNamespaceDestroyMutation from 'ee/orbit/graphql/mutations/excluded_namespace_destroy.mutation.graphql';

Vue.use(VueApollo);

describe('ExcludedGroupsCard', () => {
  let wrapper;
  let destroyHandler;
  let queryHandler;

  const group = {
    id: 'gid://gitlab/Group/1',
    name: 'Group A',
    fullPath: 'group-a',
    webPath: '/gitlab/group-a',
    avatarUrl: null,
  };

  const createComponent = async ({
    groups = [],
    pageInfo = { hasNextPage: false, endCursor: null },
    nextPage,
  } = {}) => {
    queryHandler = jest.fn().mockResolvedValueOnce({
      data: { knowledgeGraphExcludedNamespaces: { nodes: groups, pageInfo } },
    });
    if (nextPage) {
      queryHandler.mockResolvedValueOnce({
        data: { knowledgeGraphExcludedNamespaces: nextPage },
      });
    }
    destroyHandler = jest.fn().mockResolvedValue({
      data: { knowledgeGraphExcludedNamespaceDestroy: { group: { id: group.id }, errors: [] } },
    });
    const apolloProvider = createMockApollo([
      [excludedNamespacesQuery, queryHandler],
      [excludedNamespaceDestroyMutation, destroyHandler],
    ]);

    wrapper = shallowMountExtended(ExcludedGroupsCard, { apolloProvider });
    await waitForPromises();
  };

  it('shows the empty state', async () => {
    await createComponent();

    expect(wrapper.findByTestId('excluded-groups-empty-state').exists()).toBe(true);
  });

  it('shows excluded groups with a Remove button', async () => {
    await createComponent({ groups: [group] });

    expect(wrapper.text()).toContain(group.name);
    expect(wrapper.findComponent({ name: 'GlLink' }).attributes('href')).toBe(group.webPath);
    expect(
      wrapper.findAllComponents(GlButton).wrappers.some((button) => button.text() === 'Remove'),
    ).toBe(true);
  });

  it('loads more excluded groups', async () => {
    const nextGroup = {
      ...group,
      id: 'gid://gitlab/Group/2',
      name: 'Group B',
      fullPath: 'group-b',
    };
    await createComponent({
      groups: [group],
      pageInfo: { hasNextPage: true, endCursor: 'cursor-1' },
      nextPage: { nodes: [nextGroup], pageInfo: { hasNextPage: false, endCursor: 'cursor-2' } },
    });

    wrapper.findComponentByTestId('load-more-excluded-groups').vm.$emit('click');
    await waitForPromises();

    expect(queryHandler).toHaveBeenLastCalledWith(expect.objectContaining({ after: 'cursor-1' }));
    expect(wrapper.text()).toContain(nextGroup.name);
  });

  it('removes an excluded group', async () => {
    await createComponent({ groups: [group] });
    const removeButton = wrapper
      .findAllComponents(GlButton)
      .wrappers.find((button) => button.text() === 'Remove');

    removeButton.vm.$emit('click');
    await waitForPromises();

    expect(destroyHandler).toHaveBeenCalledWith({ input: { groupPath: group.fullPath } });
  });
});
