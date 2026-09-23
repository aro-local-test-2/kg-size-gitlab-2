import { GlAttributeList, GlIntersperse, GlLink, GlSkeletonLoader } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import AgentFlowDetailsPanel from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_details_panel.vue';
import AgentFlowTriggeredUser from 'ee/ai/duo_agents_platform/components/common/agent_flow_triggered_user.vue';
import { mockUser1, mockProject, mockProjectWithoutNamespace } from 'ee_jest/ai/mocks';

describe('AgentFlowDetailsPanel', () => {
  let wrapper;

  const createComponent = (props = {}, mountFn = shallowMountExtended) => {
    wrapper = mountFn(AgentFlowDetailsPanel, {
      propsData: {
        isLoading: false,
        agentFlowDefinition: 'software_development',
        aiCatalogItemPath: '',
        project: mockProject,
        user: mockUser1,
        createdAt: '2023-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
        allExecutorUrls: ['https://gitlab.com/gitlab-org/gitlab/-/jobs/456'],
        sessionId: '42',
        ...props,
      },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
      stubs: { AgentFlowTriggeredUser: stubComponent(AgentFlowTriggeredUser) },
    });
  };

  const findAttributeList = () => wrapper.findComponent(GlAttributeList);
  const findSkeletonLoaders = () => wrapper.findAllComponents(GlSkeletonLoader);
  const findRow = (label) => wrapper.findByTestId(`row-${label}`);
  const findRowValue = (label) => findRow(label).find('[data-testid="detail-value"]');
  const findTriggeredUser = () => wrapper.findComponent(AgentFlowTriggeredUser);
  const findModelBadge = () => wrapper.findByTestId('model-badge');
  const findCiJobsRow = (count) => findRowValue(count === 1 ? 'CI job' : 'CI jobs');
  const findJobIntersperse = (count = 2) => findCiJobsRow(count).findComponent(GlIntersperse);

  describe('GlAttributeList', () => {
    beforeEach(() => createComponent());

    it('renders using vertical layout', () => {
      expect(findAttributeList().props('layout')).toBe('vertical');
    });

    it('passes three sections as items', () => {
      expect(findAttributeList().props('items')).toHaveLength(3);
    });

    it('passes the Identity, Execution, and Supplemental section labels', () => {
      const labels = findAttributeList()
        .props('items')
        .map((item) => item.label);
      expect(labels).toEqual(['Identity', 'Execution', 'Supplemental']);
    });
  });

  describe('when isLoading is true', () => {
    beforeEach(() => createComponent({ isLoading: true }, mountExtended));

    it('renders a skeleton loader for each row instead of the detail value', () => {
      expect(findSkeletonLoaders().length).toBeGreaterThan(0);
      expect(wrapper.findAll('[data-testid="detail-value"]')).toHaveLength(0);
    });
  });

  describe('when isLoading is false', () => {
    beforeEach(() => createComponent({ isLoading: false }, mountExtended));

    it('renders detail values and no skeleton loaders', () => {
      expect(findSkeletonLoaders()).toHaveLength(0);
      expect(wrapper.findAll('[data-testid="detail-value"]').length).toBeGreaterThan(0);
    });
  });

  describe('Identity section', () => {
    describe('with default props', () => {
      beforeEach(() => createComponent({}, mountExtended));

      it('renders the session ID as a link to the session URL', () => {
        const link = findRowValue('Session').findComponent(GlLink);
        expect(link.text()).toBe('42');
        expect(link.attributes('href')).toBe(
          '/gitlab-org/test-project/-/automate/agent-sessions/42',
        );
      });

      it('renders the session icon', () => {
        expect(findRowValue('Session').findComponent({ name: 'GlIcon' }).props('name')).toBe(
          'session-ai',
        );
      });

      it('renders the flow name derived from agentFlowDefinition', () => {
        expect(findRowValue('Flow').text()).toContain('software_development');
      });

      it('renders the flow name as plain text', () => {
        expect(findRowValue('Flow').findComponent(GlLink).exists()).toBe(false);
      });

      it('renders the project name as a link', () => {
        const link = findRowValue('Project').findComponent(GlLink);
        expect(link.text()).toBe('Test Project');
        expect(link.attributes('href')).toBe('/gitlab-org/test-project');
      });

      it('renders the group name as a link', () => {
        const link = findRowValue('Group').findComponent(GlLink);
        expect(link.text()).toBe('gitlab-org');
        expect(link.attributes('href')).toBe('/gitlab-org');
      });

      it('renders the group icon', () => {
        expect(findRowValue('Group').findComponent({ name: 'GlIcon' }).props('name')).toBe('group');
      });
    });

    describe('when project has no paths', () => {
      beforeEach(() => createComponent({ project: { name: 'Test Project' } }, mountExtended));

      it('renders the session ID as plain text', () => {
        expect(findRowValue('Session').findComponent(GlLink).exists()).toBe(false);
        expect(findRowValue('Session').text()).toContain('42');
      });

      it('renders the project name as plain text', () => {
        expect(findRowValue('Project').findComponent(GlLink).exists()).toBe(false);
        expect(findRowValue('Project').text()).toContain('Test Project');
      });
    });

    describe('when aiCatalogItemPath is provided', () => {
      beforeEach(() =>
        createComponent({ aiCatalogItemPath: '/explore/ai-catalog/flows/1799' }, mountExtended),
      );

      it('renders the flow name as a link to the catalog item', () => {
        const link = findRowValue('Flow').findComponent(GlLink);
        expect(link.text()).toBe('software_development');
        expect(link.attributes('href')).toBe('/explore/ai-catalog/flows/1799');
      });
    });

    describe('when project has no name', () => {
      beforeEach(() => createComponent({ project: {} }, mountExtended));

      it('renders None for the project', () => {
        expect(findRowValue('Project').text()).toContain('None');
      });
    });

    describe('when project has no namespace', () => {
      beforeEach(() => createComponent({ project: mockProjectWithoutNamespace }, mountExtended));

      it('renders None for the group', () => {
        expect(findRowValue('Group').findComponent(GlLink).exists()).toBe(false);
        expect(findRowValue('Group').text()).toContain('None');
      });
    });
  });

  describe('Execution section', () => {
    beforeEach(() => createComponent({}, mountExtended));

    it('renders AgentFlowTriggeredUser with the user prop', () => {
      expect(findTriggeredUser().props('user')).toEqual(mockUser1);
    });

    it('renders the started timestamp bound to the ISO string', () => {
      expect(findRowValue('Started').find('time').attributes('datetime')).toBe(
        '2023-01-01T00:00:00Z',
      );
    });

    it('renders the last updated timestamp bound to the ISO string', () => {
      expect(findRowValue('Last updated').find('time').attributes('datetime')).toBe(
        '2024-01-01T00:00:00Z',
      );
    });

    describe('when createdAt is empty', () => {
      beforeEach(() => createComponent({ createdAt: '' }, mountExtended));

      it('does not render the started row', () => {
        expect(findRow('Started').exists()).toBe(false);
      });
    });

    describe('when updatedAt is empty', () => {
      beforeEach(() => createComponent({ updatedAt: '' }, mountExtended));

      it('does not render the last updated row', () => {
        expect(findRow('Last updated').exists()).toBe(false);
      });
    });
  });

  describe('Supplemental section', () => {
    describe('CI jobs', () => {
      describe('when one executor URL is provided', () => {
        beforeEach(() => createComponent({}, mountExtended));

        it('renders the singular CI job label', () => {
          expect(findCiJobsRow(1).exists()).toBe(true);
        });

        it('renders job link inside GlIntersperse', () => {
          expect(findJobIntersperse(1).exists()).toBe(true);
          const link = findJobIntersperse(1).findComponent(GlLink);
          expect(link.text()).toBe('456');
          expect(link.attributes('href')).toBe('https://gitlab.com/gitlab-org/gitlab/-/jobs/456');
        });

        it('renders the raw runner output hint', () => {
          expect(findCiJobsRow(1).text()).toContain('Raw runner output');
        });
      });

      describe('when multiple executor URLs are provided', () => {
        beforeEach(() =>
          createComponent(
            {
              allExecutorUrls: ['https://gitlab.com/-/jobs/123', 'https://gitlab.com/-/jobs/456'],
            },
            mountExtended,
          ),
        );

        it('renders the plural CI jobs label', () => {
          expect(findCiJobsRow(2).exists()).toBe(true);
        });

        it('renders all job links inside GlIntersperse', () => {
          const links = findJobIntersperse(2).findAllComponents(GlLink);
          expect(links).toHaveLength(2);
          expect(links.at(0).text()).toBe('123');
          expect(links.at(1).text()).toBe('456');
        });
      });

      describe('when allExecutorUrls is empty', () => {
        beforeEach(() => createComponent({ allExecutorUrls: [] }, mountExtended));

        it('renders None', () => {
          expect(findCiJobsRow(0).text()).toContain('None');
        });

        it('does not render GlIntersperse', () => {
          expect(findJobIntersperse(0).exists()).toBe(false);
        });
      });
    });

    describe('model', () => {
      describe('when modelName is provided', () => {
        beforeEach(() =>
          createComponent(
            { modelName: 'claude_sonnet_4_6', modelIdentifier: 'claude-sonnet-4-20250514' },
            mountExtended,
          ),
        );

        it('renders the model badge', () => {
          expect(findModelBadge().text()).toBe('claude_sonnet_4_6');
        });

        it('sets the model identifier as the tooltip', () => {
          expect(getBinding(findModelBadge().element, 'gl-tooltip').value).toBe(
            'claude-sonnet-4-20250514',
          );
        });
      });

      describe('when modelName is not provided', () => {
        beforeEach(() => createComponent({ modelName: '' }));

        it('does not render the model row', () => {
          expect(findRow('Default model').exists()).toBe(false);
          expect(findModelBadge().exists()).toBe(false);
        });
      });
    });
  });
});
