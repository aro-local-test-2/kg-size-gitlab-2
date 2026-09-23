import { GlBadge } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import waitForPromises from 'helpers/wait_for_promises';
import AgentFlowLinkedItems from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_linked_items.vue';

import {
  mockWorkItem,
  mockMergeRequest,
  mockWorkItemLinks,
  mockMergeRequestLinks,
  mockNoteLinks,
  mockTriggeredNoteLinks,
} from 'ee_jest/ai/mocks';

describe('AgentFlowLinkedItems', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = {} } = {}) => {
    wrapper = shallowMountExtended(AgentFlowLinkedItems, {
      propsData: {
        workItemLinks: mockWorkItemLinks,
        mergeRequestLinks: mockMergeRequestLinks,
        noteLinks: mockNoteLinks,
        ...props,
      },
      provide: {
        isSidePanelView: false,
        ...provide,
      },
      directives: {
        GlResizeObserver: createMockDirective('gl-resize-observer'),
      },
    });
  };

  const findSection = () => wrapper.findByTestId('linked-items-section');
  const findHeading = () => wrapper.findByTestId('linked-items-heading');
  const findCount = () => wrapper.findByTestId('linked-items-count');
  const findSourceBadges = () =>
    wrapper.findByTestId('linked-items-source').findAllComponents(GlBadge);
  const findCreatedBadges = () =>
    wrapper.findByTestId('linked-items-created').findAllComponents(GlBadge);

  describe('when there are linked items', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the section with the total item count', () => {
      expect(findSection().exists()).toBe(true);
      expect(findCount().text()).toBe('4 items');
    });

    it('renders the heading as an h2', () => {
      expect(findHeading().element.tagName).toBe('H2');
    });

    it('renders source work items as badges', () => {
      const badge = findSourceBadges().at(0);

      expect(findSourceBadges()).toHaveLength(1);
      expect(badge.text()).toBe('#2 Add README to project root');
      expect(badge.props('icon')).toBe('work-item-issue');
      expect(badge.attributes('href')).toBe('/gitlab-org/test-project/-/work_items/2');
    });

    it('renders created work items, merge requests, and notes as badges', () => {
      const badges = findCreatedBadges();

      expect(badges).toHaveLength(3);
      expect(badges.at(0).text()).toBe('#3 Follow-up task');
      expect(badges.at(0).props('icon')).toBe('work-item-task');
      expect(badges.at(1).text()).toBe('!8 Add README');
      expect(badges.at(1).props('icon')).toBe('git-merge');
      expect(badges.at(1).attributes('href')).toBe('/gitlab-org/test-project/-/merge_requests/8');
      expect(badges.at(2).text()).toBe('Note on !8');
      expect(badges.at(2).props('icon')).toBe('comment');
      expect(badges.at(2).attributes('href')).toBe(
        'https://gitlab.com/gitlab-org/test-project/-/merge_requests/8#note_99',
      );
    });
  });

  describe('when in side panel view', () => {
    beforeEach(() => {
      createComponent({ provide: { isSidePanelView: true } });
    });

    it('renders the heading as an h4', () => {
      expect(findHeading().element.tagName).toBe('H4');
    });
  });

  describe('when the session was triggered from a comment', () => {
    beforeEach(() => {
      createComponent({
        props: {
          workItemLinks: [],
          mergeRequestLinks: [],
          noteLinks: mockTriggeredNoteLinks,
        },
      });
    });

    it('renders the triggering comment in the source row', () => {
      const badge = findSourceBadges().at(0);

      expect(findSourceBadges()).toHaveLength(1);
      expect(badge.text()).toBe('Note on #2');
      expect(badge.props('icon')).toBe('comment');
      expect(badge.attributes('href')).toBe(
        'https://gitlab.com/gitlab-org/test-project/-/work_items/2#note_50',
      );
    });
  });

  describe('when badges overflow the first row in the side panel', () => {
    const findToggleButton = () => wrapper.findComponentByTestId('linked-items-created-toggle');

    const mockLayout = ({ firstRowCount, badgeRight = 100, containerRight = 1000 }) => {
      const container = wrapper.findByTestId('linked-items-created').element;
      container.getBoundingClientRect = () => ({ right: containerRight });
      Array.from(container.children).forEach((child, index) => {
        Object.defineProperty(child, 'offsetTop', {
          value: index < firstRowCount ? 0 : 24,
          configurable: true,
        });
        // eslint-disable-next-line no-param-reassign
        child.getBoundingClientRect = () => ({ right: badgeRight });
      });
    };

    const triggerResize = async () => {
      getBinding(findSection().element, 'gl-resize-observer').value();
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent({ provide: { isSidePanelView: true } });
      await waitForPromises();
      mockLayout({ firstRowCount: 1 });
      await triggerResize();
    });

    it('collapses the overflowing badges behind the toggle button', () => {
      const badges = findCreatedBadges();

      expect(findToggleButton().text()).toBe('+2 more');
      expect(findToggleButton().attributes('aria-expanded')).toBe('false');
      expect(badges.at(0).isVisible()).toBe(true);
      expect(badges.at(1).isVisible()).toBe(false);
      expect(badges.at(2).isVisible()).toBe(false);
    });

    describe('when the toggle button is clicked', () => {
      beforeEach(async () => {
        await findToggleButton().vm.$emit('click');
      });

      it('shows all badges behind a show less button', () => {
        const badges = findCreatedBadges();

        expect(badges.at(1).isVisible()).toBe(true);
        expect(badges.at(2).isVisible()).toBe(true);
        expect(findToggleButton().text()).toBe('Show less');
        expect(findToggleButton().attributes('aria-expanded')).toBe('true');
      });

      describe('when the toggle button is clicked again', () => {
        beforeEach(async () => {
          await findToggleButton().vm.$emit('click');
        });

        it('collapses the overflowing badges again', () => {
          expect(findCreatedBadges().at(1).isVisible()).toBe(false);
          expect(findToggleButton().text()).toBe('+2 more');
        });
      });

      describe('when a re-measure finds that all badges fit', () => {
        beforeEach(async () => {
          mockLayout({ firstRowCount: Infinity });
          await triggerResize();
        });

        it('removes the toggle button and keeps all badges visible', () => {
          expect(findCreatedBadges().at(2).isVisible()).toBe(true);
          expect(findToggleButton().exists()).toBe(false);
        });
      });
    });

    describe('when the last fitting badge leaves no room for the toggle button', () => {
      beforeEach(async () => {
        mockLayout({ firstRowCount: 2, badgeRight: 950 });
        await triggerResize();
      });

      it('hides the last fitting badge to make room', () => {
        expect(findToggleButton().text()).toBe('+2 more');
        expect(findCreatedBadges().at(1).isVisible()).toBe(false);
      });
    });

    describe('when the linked items change', () => {
      it('re-measures the rows', async () => {
        expect(findToggleButton().text()).toBe('+2 more');

        mockLayout({ firstRowCount: Infinity });
        await wrapper.setProps({ noteLinks: [] });
        await waitForPromises();

        expect(findToggleButton().exists()).toBe(false);
      });
    });
  });

  describe('in full page view', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows all badges without a show-more button', () => {
      expect(findCreatedBadges().at(1).isVisible()).toBe(true);
      expect(wrapper.findByTestId('linked-items-created-show-more').exists()).toBe(false);
    });
  });

  describe('when a note has no resolvable noteable', () => {
    beforeEach(() => {
      createComponent({
        props: {
          workItemLinks: [],
          mergeRequestLinks: [],
          noteLinks: [
            {
              linkType: 'CREATED',
              note: {
                id: 'gid://gitlab/Note/60',
                url: 'https://gitlab.com/gitlab-org/test-project/-/snippets/1#note_60',
                discussion: null,
              },
            },
          ],
        },
      });
    });

    it('falls back to a generic note label', () => {
      expect(findCreatedBadges().at(0).text()).toBe('Note');
    });
  });

  describe('when there are no linked items', () => {
    beforeEach(() => {
      createComponent({
        props: { workItemLinks: [], mergeRequestLinks: [], noteLinks: [] },
      });
    });

    it('does not render the section', () => {
      expect(findSection().exists()).toBe(false);
    });
  });

  describe('when there are no source links but legacy associations exist', () => {
    beforeEach(() => {
      createComponent({
        props: {
          workItemLinks: [],
          mergeRequestLinks: mockMergeRequestLinks,
          noteLinks: [],
          workItem: mockWorkItem,
          mergeRequest: mockMergeRequest,
        },
      });
    });

    it('falls back to the legacy work item and merge request for the source row', () => {
      const badges = findSourceBadges();

      expect(badges).toHaveLength(2);
      expect(badges.at(0).text()).toBe('#42 Legacy work item');
      expect(badges.at(0).attributes('href')).toBe('/gitlab-org/test-project/-/work_items/42');
      expect(badges.at(1).text()).toBe('!7 Legacy merge request');
      expect(badges.at(1).attributes('href')).toBe('/gitlab-org/test-project/-/merge_requests/7');
    });
  });

  describe('when source links and legacy associations both exist', () => {
    beforeEach(() => {
      createComponent({
        props: {
          workItem: mockWorkItem,
          mergeRequest: mockMergeRequest,
        },
      });
    });

    it('does not duplicate the source row with legacy items', () => {
      expect(findSourceBadges()).toHaveLength(1);
      expect(findSourceBadges().at(0).text()).toBe('#2 Add README to project root');
    });
  });

  describe('when a row has no items', () => {
    beforeEach(() => {
      createComponent({
        props: { workItemLinks: [], mergeRequestLinks: mockMergeRequestLinks, noteLinks: [] },
      });
    });

    it('does not render the empty row', () => {
      expect(wrapper.findByTestId('linked-items-source').exists()).toBe(false);
      expect(findCount().text()).toBe('1 item');
    });
  });
});
