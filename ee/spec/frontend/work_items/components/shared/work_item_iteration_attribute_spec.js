import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkItemIterationAttribute from 'ee/work_items/components/shared/work_item_iteration_attribute.vue';
import WorkItemAttribute from '~/vue_shared/components/work_item_attribute.vue';
import { workItemObjectiveMetadataWidgetsEE } from '../../mock_data';

describe('WorkItemIterations', () => {
  let wrapper;

  const { ITERATION } = workItemObjectiveMetadataWidgetsEE;

  const findIteration = () => wrapper.findComponent(WorkItemAttribute);

  const createComponent = ({ iteration, namespacePath = 'gitlab-org' } = {}) => {
    wrapper = shallowMountExtended(WorkItemIterationAttribute, {
      propsData: {
        iteration,
        namespacePath,
      },
    });
  };

  describe('iteration', () => {
    beforeEach(() => {
      createComponent({
        iteration: ITERATION.iteration,
      });
    });

    it('renders item iteration icon and name', () => {
      expect(findIteration().exists()).toBe(true);
      expect(findIteration().props('iconName')).toBe('iteration');
    });

    it('renders iteration title in title slot', () => {
      expect(wrapper.text()).toContain('Iteration title');
    });

    it('falls back to iteration period when title is absent', () => {
      createComponent({
        iteration: { ...ITERATION.iteration, title: null },
      });
      expect(wrapper.text()).toContain('Dec 19, 2023');
    });

    it('renders data attributes for popover', () => {
      expect(findIteration().attributes()).toMatchObject({
        'data-iteration': '1',
        'data-namespace-path': 'gitlab-org',
        'data-placement': 'top',
        'data-reference-type': 'iteration',
      });
      expect(findIteration().props('wrapperComponentClass')).toContain('has-popover');
    });
  });
});
