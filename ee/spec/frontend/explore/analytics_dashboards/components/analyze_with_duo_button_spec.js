import { shallowMount } from '@vue/test-utils';
import AnalyzeWithDuoButton from 'ee/explore/analytics_dashboards/components/analyze_with_duo_button.vue';
import OpenAgenticChatButton from 'ee/ai/shared/widgets/open_agentic_chat_button.vue';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { registerExternalContextProvider } from 'ee/ai/duo_agentic_chat/context/external_context_store';

jest.mock('ee/ai/duo_agentic_chat/context/external_context_store', () => ({
  ...jest.requireActual('ee/ai/duo_agentic_chat/context/external_context_store'),
  registerExternalContextProvider: jest.fn(),
}));

describe('AnalyzeWithDuoButton', () => {
  let wrapper;
  let disposeProvider;

  const glqlPanel = (title, glql) => ({ title, visualization: { data: { query: { glql } } } });

  const defaultProps = {
    namespaceFullPath: 'group/dev',
    filters: {
      dateRangeOption: 'custom',
      startDate: new Date(Date.UTC(2026, 7, 11)),
      endDate: new Date(Date.UTC(2026, 8, 10)),
    },
    panels: [
      glqlPanel(
        'Total users',
        'type = AiUsageEvent and timestamp >= "%{startDate}" and timestamp <= "%{endDate}"',
      ),
      { title: 'A section', section: { title: 'Users' } },
      { title: 'Legacy panel', visualization: 'stored_visualization_slug' },
    ],
    configPrompts: ['How is %{namespace} adopting Duo?', 'List the top projects.'],
  };

  const createComponent = (props = defaultProps) => {
    wrapper = shallowMount(AnalyzeWithDuoButton, {
      propsData: props,
    });
  };

  const findChatButton = () => wrapper.findComponent(OpenAgenticChatButton);
  const providerRegistration = () => {
    const [[category, getContent]] = registerExternalContextProvider.mock.calls;
    return { category, getContent };
  };

  beforeEach(() => {
    window.gon = { current_user_id: 7 };
    disposeProvider = jest.fn();
    registerExternalContextProvider.mockReturnValue(disposeProvider);
  });

  it('renders the agentic chat button labelled "Analyze with Duo"', () => {
    createComponent();

    expect(findChatButton().props('buttonText')).toBe('Analyze with Duo');
  });

  it('preselects the Data Analyst agent', () => {
    createComponent();

    expect(findChatButton().props('agent')).toEqual({ name: 'Data Analyst' });
  });

  it('uses the duo-chat icon', () => {
    createComponent();

    expect(findChatButton().props('icon')).toBe('duo-chat');
  });

  it('binds the session to the current user', () => {
    createComponent();

    expect(findChatButton().props('resourceId')).toBe('gid://gitlab/User/7');
  });

  it('sets a welcome message about analyzing the dashboard data', () => {
    createComponent();

    expect(findChatButton().props('welcomeMessage')).toBe(
      'Ask me about the data on this dashboard.',
    );
  });

  describe('predefined prompts', () => {
    it('interpolates the namespace full path into the config-defined prompts', () => {
      createComponent();

      expect(findChatButton().props('predefinedPrompts')).toEqual([
        'How is group/dev adopting Duo?',
        'List the top projects.',
      ]);
    });

    it('passes the raw templates as tracking labels so no namespace is tracked', () => {
      createComponent();

      expect(findChatButton().props('predefinedPromptTrackingLabels')).toEqual([
        'How is %{namespace} adopting Duo?',
        'List the top projects.',
      ]);
    });

    it('does not escape HTML-sensitive characters in the plain-text prompts', () => {
      createComponent({
        ...defaultProps,
        namespaceFullPath: 'r&d/core',
        configPrompts: ['Who are the top users in %{namespace}?'],
      });

      expect(findChatButton().props('predefinedPrompts')[0]).toBe(
        'Who are the top users in r&d/core?',
      );
    });
  });

  describe('dashboard context provider', () => {
    it('registers a dashboard_context provider and disposes it on destroy', () => {
      createComponent();

      expect(providerRegistration().category).toBe('dashboard_context');

      wrapper.destroy();

      expect(disposeProvider).toHaveBeenCalled();
    });

    it('resolves the current scope, date ranges and panel queries at read time', () => {
      createComponent();

      const content = providerRegistration().getContent();

      expect(content.dashboard_scope).toEqual({ full_path: 'group/dev', type: 'group' });
      expect(content.date_range).toEqual({
        option: 'custom',
        start_date: '2026-08-11',
        end_date: '2026-09-10',
        previous: {
          start_date: '2026-07-11',
          end_date: '2026-08-10',
        },
      });
      expect(content.panels).toEqual([
        {
          title: 'Total users',
          glql: 'type = AiUsageEvent and timestamp >= "2026-08-11" and timestamp <= "2026-09-10"',
        },
      ]);
    });

    it('instructs the agent to prefer the panel queries', () => {
      createComponent();

      const content = providerRegistration().getContent();

      expect(content.additional_instructions).toContain(
        'Use the panel queries above as your primary data source',
      );
      expect(content.additional_instructions).toContain(
        "reuse that panel's filters verbatim, change only the aggregation, and mention which panel query you used",
      );
    });

    it('labels a project scope as a project', () => {
      createComponent({ ...defaultProps, isProject: true });

      expect(providerRegistration().getContent().dashboard_scope.type).toBe('project');
    });

    it('contributes nothing while the button is hidden', () => {
      createComponent({ ...defaultProps, namespaceFullPath: '' });

      expect(providerRegistration().getContent()).toBe(null);
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks the click with the scope type and shared panel count', () => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findChatButton().vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_analyze_with_duo_on_analytics_dashboard',
        { label: 'group', value: 1 },
        undefined,
      );
    });

    it('labels project scopes as project', () => {
      createComponent({ ...defaultProps, isProject: true });
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findChatButton().vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_analyze_with_duo_on_analytics_dashboard',
        { label: 'project', value: 1 },
        undefined,
      );
    });
  });

  describe.each`
    scenario                                 | overrides
    ${'no namespace is selected'}            | ${{ namespaceFullPath: '' }}
    ${'the dashboard has no GLQL panels'}    | ${{ panels: [{ title: 'Metric panel', visualization: 'ai_impact_over_time' }] }}
    ${'the dashboard configures no prompts'} | ${{ configPrompts: [] }}
  `('when $scenario', ({ overrides }) => {
    it('renders nothing', () => {
      createComponent({ ...defaultProps, ...overrides });

      expect(findChatButton().exists()).toBe(false);
    });
  });

  describe('when there is no signed-in user', () => {
    it('renders nothing instead of throwing', () => {
      window.gon = {};

      createComponent();

      expect(findChatButton().exists()).toBe(false);
    });
  });
});
