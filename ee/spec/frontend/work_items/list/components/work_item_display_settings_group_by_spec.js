import { GlIcon, GlToggle } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import getBoardNamespaceStatusesQuery from 'ee_else_ce/work_items/board/graphql/get_namespace_statuses.query.graphql';
import WorkItemDisplaySettingsGroupBy from '~/work_items/list/components/work_item_display_settings_group_by.vue';
import { SHOW_ALL_GROUPS } from '~/work_items/board/grouping/visibility';
import { buildStatus, buildNamespaceStatusesResponse } from 'jest/work_items/board/mock_data';

Vue.use(VueApollo);

// CE's placeholder strategy never decorates a header with an icon, so real status icon
// rendering can only be exercised here. Toggling, Hide all, and the group limit are generic,
// so they're covered against CE's mocked strategy instead.
describe('WorkItemDisplaySettingsGroupBy', () => {
  let wrapper;
  let apolloProvider;

  const statuses = [buildStatus(1, 'Triage'), buildStatus(2, 'To do')];
  const status = statuses[0];
  const groupByValuesHandler = jest.fn();

  const findToggles = () => wrapper.findAllComponents(GlToggle);
  const findIcon = () => wrapper.findComponent(GlIcon);

  const createComponent = ({
    groupByValues = [status],
    visibleGroups = SHOW_ALL_GROUPS,
    props = {},
  } = {}) => {
    groupByValuesHandler.mockResolvedValue(buildNamespaceStatusesResponse(groupByValues));

    apolloProvider = createMockApollo([[getBoardNamespaceStatusesQuery, groupByValuesHandler]]);

    wrapper = shallowMountExtended(WorkItemDisplaySettingsGroupBy, {
      apolloProvider,
      propsData: {
        fullPath: 'group/full/path',
        workItemTypeId: 'gid://gitlab/WorkItems::Type/1',
        namespacePreferences: { visibleGroups },
        ...props,
      },
    });
  };

  it('renders the status icon alongside its toggle', async () => {
    createComponent();
    await waitForPromises();

    expect(findToggles()).toHaveLength(1);
    expect(findIcon().props('name')).toBe(status.iconName);
    expect(findIcon().attributes('style')).toContain('color:');
  });

  describe('rendering', () => {
    it('renders an enabled toggle for each status, shown by default', async () => {
      createComponent({ groupByValues: statuses });
      await waitForPromises();

      const toggles = findToggles();
      expect(toggles).toHaveLength(2);
      expect(toggles.at(0).props()).toMatchObject({ value: true, label: 'Triage' });
      expect(toggles.at(1).props()).toMatchObject({ value: true, label: 'To do' });
    });
  });
});
