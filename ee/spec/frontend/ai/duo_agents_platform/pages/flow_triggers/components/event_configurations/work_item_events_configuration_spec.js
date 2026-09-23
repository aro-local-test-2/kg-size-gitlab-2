import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import namespaceWorkItemTypesQuery from '~/work_items/graphql/namespace_work_item_types.query.graphql';
import { namespaceWorkItemTypesQueryResponse } from 'jest/work_items/mock_data';
import WorkItemEventsConfiguration from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/work_item_events_configuration.vue';
import EventActionsConfiguration from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/event_actions_configuration.vue';

jest.mock('~/alert');

Vue.use(VueApollo);

const buildActionFilter = (actions) => ({
  work_item: { rules: [{ field: 'action', operator: 'in', value: actions }] },
});

const buildFullFilter = (actions, statusNames) => ({
  work_item: {
    rules: [
      { field: 'action', operator: 'in', value: actions },
      { field: 'status.name', operator: 'in', value: statusNames },
    ],
  },
});

describe('WorkItemEventsConfiguration', () => {
  let wrapper;
  let queryHandler;

  const createComponent = async ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(WorkItemEventsConfiguration, {
      apolloProvider: createMockApollo([[namespaceWorkItemTypesQuery, queryHandler]]),
      provide: { projectPath: 'gitlab-org/gitlab-test' },
      propsData: {
        value: {},
        ...props,
      },
    });

    await waitForPromises();
  };

  const findActionsConfiguration = () => wrapper.findComponent(EventActionsConfiguration);
  const findStatusFormGroup = () => wrapper.findByTestId('status-form-group');
  const findStatusListbox = () => wrapper.findComponent(GlCollapsibleListbox);

  beforeEach(() => {
    queryHandler = jest.fn().mockResolvedValue(namespaceWorkItemTypesQueryResponse);
  });

  describe('action picker', () => {
    const filter = buildActionFilter(['created']);

    beforeEach(async () => {
      await createComponent({
        props: { value: filter, invalidFeedback: 'Select at least one action.' },
      });
    });

    it('renders EventActionsConfiguration for the work_item scope', () => {
      expect(findActionsConfiguration().props()).toMatchObject({
        scope: 'work_item',
        field: 'action',
        value: filter,
        invalidFeedback: 'Select at least one action.',
      });
    });
  });

  describe('status listbox', () => {
    describe('when "status_changed" is not selected', () => {
      beforeEach(async () => {
        await createComponent({ props: { value: buildActionFilter(['created']) } });
      });

      it('is not rendered', () => {
        expect(findStatusFormGroup().exists()).toBe(false);
      });

      it('does not fetch statuses', () => {
        expect(queryHandler).not.toHaveBeenCalled();
      });
    });

    describe('when "status_changed" is the only selected action', () => {
      beforeEach(async () => {
        await createComponent({ props: { value: buildActionFilter(['status_changed']) } });
      });

      it('is enabled', () => {
        expect(findStatusListbox().props('disabled')).toBe(false);
      });

      it('is labelled by the form group', () => {
        expect(findStatusFormGroup().attributes('label-for')).toBe(
          findStatusListbox().props('toggleId'),
        );
      });

      it('fetches the statuses of the project', () => {
        expect(queryHandler).toHaveBeenCalledWith({ fullPath: 'gitlab-org/gitlab-test' });
      });

      it('lists each status name once', () => {
        const values = findStatusListbox()
          .props('items')
          .map((item) => item.value);

        expect(values).toEqual(expect.arrayContaining(['To do', 'In progress', 'Done']));
        expect(new Set(values).size).toBe(values.length);
      });

      it('shows "Any status" when nothing is selected', () => {
        expect(findStatusListbox().props('toggleText')).toBe('Any status');
        expect(findStatusListbox().props('selected')).toEqual([]);
      });

      it('adds a status.name rule when statuses are selected', () => {
        findStatusListbox().vm.$emit('select', ['In progress', 'Done']);

        expect(wrapper.emitted('input')).toEqual([
          [buildFullFilter(['status_changed'], ['In progress', 'Done'])],
        ]);
      });
    });

    describe('when "status_changed" is selected with another action', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildActionFilter(['created', 'status_changed']) },
        });
      });

      it('is disabled with a hint', () => {
        expect(findStatusListbox().props('disabled')).toBe(true);
        expect(findStatusFormGroup().attributes('description')).toBe(
          'Available only when Status changed is the only selected action.',
        );
      });
    });

    describe('when the status query fails', () => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockRejectedValue(new Error('boom'));
        await createComponent({ props: { value: buildActionFilter(['status_changed']) } });
      });

      it('shows an alert', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'Something went wrong while fetching work item statuses. Please try again.',
          }),
        );
      });

      it('explains the empty listbox', () => {
        expect(findStatusListbox().props('items')).toEqual([]);
        expect(findStatusListbox().props('noResultsText')).toBe(
          'Could not load statuses. Refresh the page to try again.',
        );
      });

      describe('when a later refetch succeeds', () => {
        beforeEach(async () => {
          queryHandler.mockResolvedValue(namespaceWorkItemTypesQueryResponse);
          // Deselecting and reselecting "status_changed" toggles `skip`, which refetches.
          await wrapper.setProps({ value: buildActionFilter(['created']) });
          await wrapper.setProps({ value: buildActionFilter(['status_changed']) });
          await waitForPromises();
        });

        it('clears the failure text', () => {
          expect(findStatusListbox().props('items')).not.toEqual([]);
          expect(findStatusListbox().props('noResultsText')).not.toBe(
            'Could not load statuses. Refresh the page to try again.',
          );
        });
      });
    });

    describe('with a status.name rule', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFullFilter(['status_changed'], ['In progress', 'Done']) },
        });
      });

      it('shows the selected statuses', () => {
        expect(findStatusListbox().props('selected')).toEqual(['In progress', 'Done']);
        expect(findStatusListbox().props('toggleText')).toBe('In progress, Done');
      });

      it('replaces the rule when the selection changes', () => {
        findStatusListbox().vm.$emit('select', ['Done']);

        expect(wrapper.emitted('input')).toEqual([[buildFullFilter(['status_changed'], ['Done'])]]);
      });

      it('removes the rule when the selection is cleared', () => {
        findStatusListbox().vm.$emit('select', []);

        expect(wrapper.emitted('input')).toEqual([[buildActionFilter(['status_changed'])]]);
      });
    });

    describe('with a status.name rule using another operator', () => {
      beforeEach(async () => {
        await createComponent({
          props: {
            value: {
              work_item: {
                rules: [
                  { field: 'action', operator: 'in', value: ['status_changed'] },
                  { field: 'status.name', operator: 'eq', value: 'In progress' },
                ],
              },
            },
          },
        });
      });

      it('shows no selection', () => {
        expect(findStatusListbox().props('selected')).toEqual([]);
      });

      it('replaces the foreign rule on selection', () => {
        findStatusListbox().vm.$emit('select', ['Done']);

        expect(wrapper.emitted('input')).toEqual([[buildFullFilter(['status_changed'], ['Done'])]]);
      });
    });
  });

  describe('when the action selection changes', () => {
    beforeEach(async () => {
      await createComponent({
        props: { value: buildFullFilter(['status_changed'], ['In progress']) },
      });
    });

    it('keeps the status rule while "status_changed" is the only action', () => {
      const nextFilter = buildFullFilter(['status_changed'], ['In progress']);
      findActionsConfiguration().vm.$emit('input', nextFilter);

      expect(wrapper.emitted('input')).toEqual([[nextFilter]]);
    });

    it('drops the status rule when another action is added', () => {
      findActionsConfiguration().vm.$emit(
        'input',
        buildFullFilter(['created', 'status_changed'], ['In progress']),
      );

      expect(wrapper.emitted('input')).toEqual([
        [buildActionFilter(['created', 'status_changed'])],
      ]);
    });

    it('drops the status rule when "status_changed" is deselected', () => {
      findActionsConfiguration().vm.$emit('input', buildFullFilter(['created'], ['In progress']));

      expect(wrapper.emitted('input')).toEqual([[buildActionFilter(['created'])]]);
    });

    it('emits an empty filter when every action is deselected', () => {
      findActionsConfiguration().vm.$emit('input', {
        work_item: { rules: [{ field: 'status.name', operator: 'in', value: ['In progress'] }] },
      });

      expect(wrapper.emitted('input')).toEqual([[{}]]);
    });
  });
});
