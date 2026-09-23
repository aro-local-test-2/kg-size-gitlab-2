import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentTodos from 'ee/ai/duo_agents_platform/pages/show/components/agent_todos.vue';
import TodoChecklist from 'ee/ai/duo_agents_platform/components/common/todo_checklist.vue';

const buildTodoMessage = (todos) => ({
  toolInfo: JSON.stringify({ name: 'todo_write', args: { todos } }),
});

const mockTodos = [
  { status: 'completed', description: 'Read repository' },
  { status: 'in_progress', description: 'Extract logic' },
  { status: 'pending', description: 'Add tests' },
];

const mockDuoMessages = [buildTodoMessage(mockTodos)];

describe('AgentTodos', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AgentTodos, {
      propsData: {
        status: 'RUNNING',
        duoMessages: mockDuoMessages,
        ...props,
      },
    });
  };

  const findPlanSection = () => wrapper.findByTestId('plan-section');
  const findTodoChecklist = () => wrapper.findComponent(TodoChecklist);
  const findTodosHeading = () => wrapper.findByTestId('todos-heading');
  const findTodoProgressSummary = () => wrapper.findByTestId('todo-progress-summary');

  describe('when there are todo_write messages', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the Plan section', () => {
      expect(findPlanSection().exists()).toBe(true);
    });

    it('renders the Agent todos heading', () => {
      expect(findTodosHeading().text()).toBe('Agent todos');
    });

    it('renders the completed count out of the total in the header', () => {
      expect(findTodoProgressSummary().text()).toBe('1 of 3');
    });

    it('passes the latest todo tool info to TodoChecklist', () => {
      expect(findTodoChecklist().props('toolInfo')).toMatchObject({
        name: 'todo_write',
        args: { todos: mockTodos },
      });
    });

    it('renders the TodoChecklist without a border', () => {
      expect(findTodoChecklist().props('bordered')).toBe(false);
    });

    it('renders the heading as an h2', () => {
      expect(findTodosHeading().element.tagName).toBe('H2');
    });
  });

  describe('when rendered in the side panel', () => {
    beforeEach(() => {
      createComponent({ isSidePanelView: true });
    });

    it('renders the heading as an h4', () => {
      expect(findTodosHeading().element.tagName).toBe('H4');
    });
  });

  describe('when multiple todo_write messages exist', () => {
    const laterTodos = [{ status: 'completed', description: 'All done' }];

    beforeEach(() => {
      createComponent({
        duoMessages: [buildTodoMessage(mockTodos), buildTodoMessage(laterTodos)],
      });
    });

    it('passes the latest todo state to TodoChecklist', () => {
      expect(findTodoChecklist().props('toolInfo').args.todos).toEqual(laterTodos);
    });
  });

  describe('when there are no todo_write messages', () => {
    beforeEach(() => {
      createComponent({ duoMessages: [] });
    });

    it('does not render the Plan section', () => {
      expect(findPlanSection().exists()).toBe(false);
    });

    it('does not render the TodoChecklist', () => {
      expect(findTodoChecklist().exists()).toBe(false);
    });
  });

  describe.each`
    status        | flowFinished
    ${'RUNNING'}  | ${false}
    ${'FINISHED'} | ${true}
    ${'FAILED'}   | ${true}
    ${'STOPPED'}  | ${true}
  `('when the session status is $status', ({ status, flowFinished }) => {
    beforeEach(() => {
      createComponent({ status });
    });

    it(`passes flowFinished=${flowFinished} to TodoChecklist`, () => {
      expect(findTodoChecklist().props('flowFinished')).toBe(flowFinished);
    });
  });
});
