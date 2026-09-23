import { GlBadge, GlCollapse, GlIcon, GlLink, GlSkeletonLoader } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import AgentFlowDetailsOverlay from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_details_overlay.vue';

describe('AgentFlowDetailsOverlay', () => {
  let wrapper;

  const defaultProps = {
    workflowId: '5541972',
    project: { fullPath: 'gitlab-org/gitlab' },
    agentFlowDefinition: 'Developer',
    flowVersion: 'v1',
    allExecutorUrls: ['https://gitlab.com/gitlab-org/gitlab/-/jobs/15336342577'],
    modelName: 'claude_sonnet_4_6_vertex',
    modelIdentifier: 'claude-sonnet-4-6-20260514',
  };

  const createComponent = ({ props = {}, mountFn = mountExtended } = {}) => {
    wrapper = mountFn(AgentFlowDetailsOverlay, {
      propsData: { ...defaultProps, ...props },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findToggle = () => wrapper.findByTestId('details-overlay-toggle');
  const findCollapse = () => wrapper.findComponent(GlCollapse);
  const findChevron = () => wrapper.findComponent(GlIcon);
  const findSessionId = () => wrapper.findByTestId('session-id');
  const findFlow = () => wrapper.findByTestId('flow');
  const findCiJobs = () => wrapper.findByTestId('ci-jobs');
  const findCiJobsLabel = () => wrapper.findByTestId('ci-jobs-label');
  const findDefaultModel = () => wrapper.findByTestId('default-model');
  const findModelBadge = () => wrapper.findComponent(GlBadge);
  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);

  describe('toggle', () => {
    beforeEach(() => createComponent());

    it('renders the heading', () => {
      expect(findToggle().text()).toContain('Session details');
    });

    it('points aria-controls at the collapsible content', () => {
      expect(findToggle().attributes('aria-controls')).toBe(findCollapse().attributes('id'));
    });

    describe('when clicked', () => {
      beforeEach(() => findToggle().trigger('click'));

      it('emits toggle', () => {
        expect(wrapper.emitted('toggle')).toHaveLength(1);
      });
    });
  });

  describe('when collapsed', () => {
    beforeEach(() => createComponent({ props: { visible: false }, mountFn: shallowMountExtended }));

    it('collapses the content', () => {
      expect(findCollapse().props('visible')).toBe(false);
    });

    it('reports the collapsed state to screen readers', () => {
      expect(findToggle().attributes('aria-expanded')).toBe('false');
    });

    it('points the chevron up', () => {
      expect(findChevron().props('name')).toBe('chevron-up');
    });
  });

  describe('when expanded', () => {
    beforeEach(() => createComponent({ props: { visible: true }, mountFn: shallowMountExtended }));

    it('expands the content', () => {
      expect(findCollapse().props('visible')).toBe(true);
    });

    it('reports the expanded state to screen readers', () => {
      expect(findToggle().attributes('aria-expanded')).toBe('true');
    });

    it('points the chevron down', () => {
      expect(findChevron().props('name')).toBe('chevron-down');
    });
  });

  describe('when the session is still loading', () => {
    beforeEach(() => createComponent({ props: { isLoading: true, visible: true } }));

    it('renders a skeleton in place of the rows', () => {
      expect(findSkeleton().exists()).toBe(true);
      expect(findSessionId().exists()).toBe(false);
      expect(findFlow().exists()).toBe(false);
      expect(findCiJobs().exists()).toBe(false);
    });

    it('leaves the summary empty rather than describing absent data', () => {
      expect(findToggle().text()).toBe('Session details');
    });
  });

  describe('summary', () => {
    const summaryText = () => findToggle().text();

    describe('when the session has both CI jobs and a model', () => {
      beforeEach(() => createComponent());

      it('lists the session ID, CI job, and model', () => {
        expect(summaryText()).toContain('Session ID, CI job, Model');
      });
    });

    describe('when the session has no model', () => {
      beforeEach(() => createComponent({ props: { modelName: '' } }));

      it('drops the model', () => {
        expect(summaryText()).toContain('Session ID, CI job');
        expect(summaryText()).not.toContain('Model');
      });
    });

    describe('when the session has several CI jobs', () => {
      beforeEach(() =>
        createComponent({
          props: {
            allExecutorUrls: [
              'https://gitlab.com/gitlab-org/gitlab/-/jobs/1',
              'https://gitlab.com/gitlab-org/gitlab/-/jobs/2',
            ],
          },
        }),
      );

      it('pluralizes CI jobs', () => {
        expect(summaryText()).toContain('Session ID, CI jobs, Model');
      });
    });

    describe('when the session has no CI jobs', () => {
      beforeEach(() => createComponent({ props: { allExecutorUrls: [] } }));

      it('drops the CI job', () => {
        expect(summaryText()).toContain('Session ID, Model');
      });
    });

    describe('when no executor url has a numeric job id', () => {
      beforeEach(() =>
        createComponent({ props: { allExecutorUrls: ['https://gitlab.com/not-a-job'] } }),
      );

      it('drops the CI job', () => {
        expect(summaryText()).toContain('Session ID, Model');
      });
    });

    describe('when the session has neither CI jobs nor a model', () => {
      beforeEach(() => createComponent({ props: { allExecutorUrls: [], modelName: '' } }));

      it('lists the session ID alone', () => {
        expect(summaryText()).toContain('Session ID');
        expect(summaryText()).not.toContain('CI job');
      });
    });
  });

  describe('session ID', () => {
    beforeEach(() => createComponent());

    it('links to the session page', () => {
      expect(findSessionId().findComponent(GlLink).attributes('href')).toBe(
        '/gitlab-org/gitlab/-/automate/agent-sessions/5541972',
      );
    });

    it('renders the id', () => {
      expect(findSessionId().text()).toBe('5541972');
    });

    describe('when the project path is unavailable', () => {
      beforeEach(() => createComponent({ props: { project: {} } }));

      it('renders the id as plain text', () => {
        expect(findSessionId().findComponent(GlLink).exists()).toBe(false);
        expect(findSessionId().text()).toBe('5541972');
      });
    });
  });

  describe('flow', () => {
    describe('when a version is resolved', () => {
      beforeEach(() => createComponent());

      it('appends the version to the flow name', () => {
        expect(findFlow().text()).toBe('Developer · v1');
      });
    });

    describe('when no version is resolved', () => {
      beforeEach(() => createComponent({ props: { flowVersion: '' } }));

      it('renders the flow name alone', () => {
        expect(findFlow().text()).toBe('Developer');
      });
    });

    describe('when the session ran a catalog item', () => {
      beforeEach(() =>
        createComponent({ props: { aiCatalogItemPath: '/explore/ai-catalog/flows/1799' } }),
      );

      it('links the flow to the catalog item', () => {
        const link = findFlow().findComponent(GlLink);

        expect(link.text()).toBe('Developer · v1');
        expect(link.attributes('href')).toBe('/explore/ai-catalog/flows/1799');
      });
    });

    describe('when the session has no catalog item', () => {
      beforeEach(() => createComponent());

      it('renders the flow as plain text', () => {
        expect(findFlow().findComponent(GlLink).exists()).toBe(false);
      });
    });
  });

  describe('CI jobs', () => {
    describe('with a single executor log url', () => {
      beforeEach(() => createComponent());

      it('links the job derived from the url', () => {
        const link = findCiJobs().findComponent(GlLink);

        expect(link.text()).toBe('15336342577');
        expect(link.attributes('href')).toBe(
          'https://gitlab.com/gitlab-org/gitlab/-/jobs/15336342577',
        );
      });
    });

    describe('with several executor log urls', () => {
      beforeEach(() =>
        createComponent({
          props: {
            allExecutorUrls: [
              'https://gitlab.com/gitlab-org/gitlab/-/jobs/1',
              'https://gitlab.com/gitlab-org/gitlab/-/jobs/2',
            ],
          },
        }),
      );

      it('lists every job', () => {
        expect(findCiJobs().findAllComponents(GlLink)).toHaveLength(2);
      });

      it('labels the row CI jobs', () => {
        expect(findCiJobsLabel().text()).toBe('CI jobs');
      });
    });

    describe('when a url has no numeric job id', () => {
      beforeEach(() =>
        createComponent({ props: { allExecutorUrls: ['https://gitlab.com/not-a-job'] } }),
      );

      it('renders None', () => {
        expect(findCiJobs().findComponent(GlLink).exists()).toBe(false);
        expect(findCiJobs().text()).toBe('None');
      });
    });

    describe('when there are no executor urls', () => {
      beforeEach(() => createComponent({ props: { allExecutorUrls: [] } }));

      it('renders None', () => {
        expect(findCiJobs().text()).toBe('None');
      });
    });
  });

  describe('default model', () => {
    describe('when a model is resolved', () => {
      beforeEach(() => createComponent());

      it('renders the model name in a badge', () => {
        expect(findModelBadge().text()).toBe('claude_sonnet_4_6_vertex');
      });

      it('shows the provider model identifier in a tooltip', () => {
        expect(getBinding(findModelBadge().element, 'gl-tooltip').value).toBe(
          defaultProps.modelIdentifier,
        );
      });
    });

    describe('when no model is resolved', () => {
      beforeEach(() => createComponent({ props: { modelName: '' } }));

      it('omits the row', () => {
        expect(findDefaultModel().exists()).toBe(false);
        expect(findModelBadge().exists()).toBe(false);
      });
    });
  });
});
