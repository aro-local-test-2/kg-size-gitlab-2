import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox, GlModal } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import ExcludeGroupModal from 'ee/orbit/components/exclude_group_modal.vue';
import excludableNamespacesQuery from 'ee/orbit/graphql/queries/excludable_namespaces.query.graphql';
import excludedNamespaceCreateMutation from 'ee/orbit/graphql/mutations/excluded_namespace_create.mutation.graphql';

Vue.use(VueApollo);

describe('ExcludeGroupModal', () => {
  let wrapper;
  let mutationHandler;

  const group = { id: 'gid://gitlab/Group/1', name: 'Group A', fullPath: 'group-a' };

  const createComponent = ({ excludedPaths = [], data = {} } = {}) => {
    const queryHandler = jest.fn().mockResolvedValue({ data: { groups: { nodes: [group] } } });
    mutationHandler = jest.fn().mockResolvedValue({
      data: { knowledgeGraphExcludedNamespaceCreate: { group, errors: [] } },
    });
    const apolloProvider = createMockApollo([
      [excludableNamespacesQuery, queryHandler],
      [excludedNamespaceCreateMutation, mutationHandler],
    ]);

    wrapper = shallowMount(ExcludeGroupModal, {
      apolloProvider,
      propsData: { visible: true, excludedPaths },
      data() {
        return { groups: [group], ...data };
      },
    });
  };

  it('lists top-level groups that are not already excluded', async () => {
    createComponent();
    await waitForPromises();

    expect(wrapper.findComponent(GlCollapsibleListbox).props('items')).toEqual([
      { value: group.fullPath, text: group.name },
    ]);
  });

  it('filters groups that are already excluded', async () => {
    createComponent({ excludedPaths: [group.fullPath] });
    await waitForPromises();

    expect(wrapper.findComponent(GlCollapsibleListbox).props('items')).toEqual([]);
  });

  it('excludes the selected group', async () => {
    createComponent();
    await waitForPromises();
    wrapper.findComponent(GlCollapsibleListbox).vm.$emit('select', group.fullPath);
    await nextTick();

    wrapper.findComponent(GlModal).vm.$emit('primary', { preventDefault: jest.fn() });
    await waitForPromises();

    expect(mutationHandler).toHaveBeenCalledWith({ input: { groupPath: group.fullPath } });
  });

  it('warns that an existing index is removed within a few minutes', () => {
    createComponent();

    expect(wrapper.text()).toContain('removes its enrollment and index within a few minutes');
  });
});
