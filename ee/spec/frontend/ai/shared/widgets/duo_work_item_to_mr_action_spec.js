import { shallowMount } from '@vue/test-utils';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import DuoWorkflowAction from 'ee/ai/shared/widgets/duo_workflow_action.vue';

describe('DuoWorkItemToMrAction component', () => {
  let wrapper;

  const defaultProps = {
    projectPath: 'group/project',
    workItemIid: '42',
    workItemType: 'Issue',
    workItemWebUrl: 'http://gdk.test/group/project/-/issues/42',
  };

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMount(DuoWorkItemToMrAction, {
      propsData: {
        ...defaultProps,
        ...props,
      },
    });
  };

  const findDuoWorkflowAction = () => wrapper.findComponent(DuoWorkflowAction);

  beforeEach(() => {
    window.gon = { current_username: 'testuser' };
  });

  describe('default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders DuoWorkflowAction', () => {
      expect(findDuoWorkflowAction().exists()).toBe(true);
    });

    it('passes correct props to DuoWorkflowAction', () => {
      expect(findDuoWorkflowAction().props()).toMatchObject({
        projectPath: 'group/project',
        hoverMessage: 'Implement work item with GitLab Duo',
        goal: expect.stringContaining(
          '@testuser assigned you to solve the following issue: http://gdk.test/group/project/-/issues/42',
        ),
        workflowDefinition: 'developer/v1',
        agentPrivileges: [1, 2, 3, 4, 5],
        size: 'medium',
        variant: 'default',
        category: 'primary',
        workItemIid: '42',
      });
    });

    it('renders slot text', () => {
      expect(findDuoWorkflowAction().text()).toBe('Implement');
    });

    it('passes the correct source prop', () => {
      expect(findDuoWorkflowAction().props('source')).toBe('work_item_to_merge_request');
    });

    it('asks the agent to notify the assigner once the work is done', () => {
      expect(findDuoWorkflowAction().props('goal')).toContain(
        '@mention @testuser in a comment on the issue',
      );
    });
  });

  describe('when generateMrButtonOptions is provided', () => {
    beforeEach(() => {
      createComponent({
        props: {
          generateMrButtonOptions: { size: 'small', variant: 'confirm', category: 'secondary' },
        },
      });
    });

    it('forwards them to DuoWorkflowAction', () => {
      expect(findDuoWorkflowAction().props()).toMatchObject({
        size: 'small',
        variant: 'confirm',
        category: 'secondary',
      });
    });
  });

  describe('when workItemType is not an issue', () => {
    beforeEach(() => {
      createComponent({ props: { workItemType: 'Epic' } });
    });

    it('uses the lowercased workItemType in the goal', () => {
      expect(findDuoWorkflowAction().props('goal')).toContain(
        '@testuser assigned you to solve the following epic:',
      );
    });
  });

  describe('when current_username is not set', () => {
    beforeEach(() => {
      window.gon = {};
      createComponent();
    });

    it('uses an empty username in the goal', () => {
      expect(findDuoWorkflowAction().props('goal')).toContain(
        '@ assigned you to solve the following issue:',
      );
    });
  });

  describe('when additionalGoalContext is provided', () => {
    beforeEach(() => {
      createComponent({ props: { additionalGoalContext: 'Read the workplan first.' } });
    });

    it('prepends the context before the base goal', () => {
      expect(findDuoWorkflowAction().props('goal')).toMatch(
        /^Read the workplan first\.\n\n@testuser assigned you/,
      );
    });
  });

  describe('when additionalGoalContext is not provided', () => {
    beforeEach(() => {
      createComponent();
    });

    it('starts with the base goal directly', () => {
      expect(findDuoWorkflowAction().props('goal')).toMatch(/^@testuser assigned you/);
    });
  });
});
