import { GlAvatar, GlDisclosureDropdown } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import { TEST_HOST } from 'helpers/test_constants';
import toast from '~/vue_shared/plugins/global_toast';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import DecisionLogItem from 'ee/work_items/components/decision_log/decision_log_item.vue';
import DecisionLogContext from 'ee/work_items/components/decision_log/decision_log_context.vue';
import { mockDecision, buildMockDecision, buildMockOptions } from './mock_data';

jest.mock('~/vue_shared/plugins/global_toast');

const WORK_ITEM_URL = 'http://test.host/group/-/work_items/7';

describe('DecisionLogItem', () => {
  let wrapper;

  const scrollIntoView = jest.fn();
  HTMLElement.prototype.scrollIntoView = scrollIntoView;

  const settledOption = mockDecision.options.nodes.find((option) => option.selected);
  const unsettledOption = mockDecision.options.nodes.find((option) => !option.selected);

  const createComponent = ({
    decision = mockDecision,
    workItemWebUrl = WORK_ITEM_URL,
    targetAnchor = '',
  } = {}) => {
    wrapper = mountExtended(DecisionLogItem, {
      propsData: { decision, workItemWebUrl, targetAnchor },
    });
  };

  const findAnswer = () => wrapper.findByTestId('decision-answer');
  const findAllAnswers = () => wrapper.findAllByTestId('decision-answer');
  const findQuestion = () => wrapper.findByTestId('decision-question');
  const findDecidedBy = () => wrapper.findByTestId('decision-decided-by');
  const findAvatar = () => wrapper.findComponent(GlAvatar);
  const findTimeagoTooltip = () => wrapper.findComponent(TimeAgoTooltip);
  const findSourceLink = () => wrapper.findComponentByTestId('decision-source-link');
  const findContext = () => wrapper.findComponent(DecisionLogContext);
  const findCard = () => wrapper.findByTestId('decision-log-item');
  const findCopyLinkAction = () => wrapper.findComponentByTestId('copy-decision-link-action');
  const findActionsDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findEditAction = () => wrapper.findComponentByTestId('edit-decision-action');
  const findArchiveAction = () => wrapper.findComponentByTestId('archive-decision-action');
  const findArchivedBadge = () => wrapper.findByTestId('decision-archived-badge');

  beforeEach(() => {
    setWindowLocation('/group/-/work_items/7');
  });

  describe('when nobody is recorded as having resolved the decision', () => {
    beforeEach(() => {
      createComponent({ decision: buildMockDecision({ resolvedBy: null }) });
    });

    it('drops the attribution', () => {
      expect(findDecidedBy().exists()).toBe(false);
      expect(findAvatar().exists()).toBe(false);
    });

    it('still says when it was decided', () => {
      expect(findTimeagoTooltip().props('time')).toBe(mockDecision.resolvedAt);
    });
  });

  describe('when the decision has no resolved time', () => {
    beforeEach(() => {
      createComponent({ decision: buildMockDecision({ resolvedAt: null }) });
    });

    it('drops the timestamp', () => {
      expect(findTimeagoTooltip().exists()).toBe(false);
    });
  });

  describe('when a decision settled a question', () => {
    beforeEach(() => {
      createComponent();
    });

    it('leads with the settled option', () => {
      expect(findAnswer().text()).toBe(settledOption.content);
    });

    it('names who settled it and when', () => {
      expect(findDecidedBy().text()).toBe(mockDecision.resolvedBy.name);
      expect(findAvatar().props('entityName')).toBe(mockDecision.resolvedBy.name);
      expect(findTimeagoTooltip().props('time')).toBe(mockDecision.resolvedAt);
    });

    it('reads the question under the decision', () => {
      expect(findQuestion().text()).toBe(mockDecision.title);
    });

    it('hands the context and the rationale to the context block', () => {
      expect(findContext().props()).toMatchObject({
        context: mockDecision.description,
        rationale: mockDecision.resolutionRationale,
      });
    });
  });

  describe('when a decision settled several options', () => {
    const bothSettled = [
      { ...unsettledOption, selected: true },
      { ...settledOption, selected: true },
    ];

    beforeEach(() => {
      createComponent({
        decision: buildMockDecision({ options: buildMockOptions(bothSettled) }),
      });
    });

    it('lists every settled option', () => {
      expect(findAllAnswers().wrappers.map((answer) => answer.text())).toEqual(
        bothSettled.map((option) => option.content),
      );
    });
  });

  describe('when no option was settled', () => {
    beforeEach(() => {
      createComponent({
        decision: buildMockDecision({ options: buildMockOptions([unsettledOption]) }),
      });
    });

    it('makes the question the header', () => {
      expect(findAnswer().text()).toBe(mockDecision.title);
    });

    it('does not repeat the question underneath', () => {
      expect(findQuestion().exists()).toBe(false);
    });
  });

  describe('when the decision was marked from a thread', () => {
    beforeEach(() => {
      createComponent({ decision: buildMockDecision({ title: null }) });
    });

    it('renders the decision without a question', () => {
      expect(findAnswer().exists()).toBe(true);
      expect(findQuestion().exists()).toBe(false);
    });
  });

  describe('when the decision has neither context nor rationale', () => {
    beforeEach(() => {
      createComponent({
        decision: buildMockDecision({ description: null, resolutionRationale: null }),
      });
    });

    it('does not render the context block', () => {
      expect(findContext().exists()).toBe(false);
    });
  });

  describe('source link', () => {
    describe('when the decision was made in a note', () => {
      beforeEach(() => {
        createComponent();
      });

      it('anchors to the note', () => {
        expect(findSourceLink().attributes('href')).toBe(mockDecision.noteUrl);
      });
    });

    describe('when the decision was recorded by hand', () => {
      const sourceLink = `${TEST_HOST}/acme/web/-/issues/12`;

      beforeEach(() => {
        createComponent({ decision: buildMockDecision({ noteUrl: null, sourceLink }) });
      });

      it('anchors to the source the author gave', () => {
        expect(findSourceLink().attributes('href')).toBe(sourceLink);
      });
    });

    describe('when the source is inside GitLab', () => {
      beforeEach(() => {
        createComponent();
      });

      it('opens in the same tab, because the panel can move aside for it', () => {
        expect(findSourceLink().attributes('target')).toBeUndefined();
      });

      it('is not marked as an external link', () => {
        expect(findSourceLink().props('showExternalIcon')).toBe(false);
      });

      it('asks for the panel to get out of the way when followed', () => {
        findSourceLink().vm.$emit('click');

        expect(wrapper.emitted('view-comment')).toHaveLength(1);
      });
    });

    describe('when the source is outside GitLab', () => {
      beforeEach(() => {
        createComponent({
          decision: buildMockDecision({
            noteUrl: null,
            sourceLink: 'https://docs.example.com/saml-rollout',
          }),
        });
      });

      it('opens in a new tab, so the reader keeps the work item', () => {
        expect(findSourceLink().attributes('target')).toBe('_blank');
      });

      it('tells the reader the link leaves GitLab', () => {
        expect(findSourceLink().props('showExternalIcon')).toBe(true);
      });

      it('leaves the panel open, because nothing behind it is being visited', () => {
        findSourceLink().vm.$emit('click');

        expect(wrapper.emitted('view-comment')).toBeUndefined();
      });
    });

    describe('when the decision carries both a source and a note', () => {
      const sourceLink = `${TEST_HOST}/acme/web/-/issues/12`;

      beforeEach(() => {
        createComponent({ decision: buildMockDecision({ sourceLink }) });
      });

      it('prefers the source, because the author chose it', () => {
        expect(findSourceLink().attributes('href')).toBe(sourceLink);
      });
    });

    describe('when there is nothing to point at', () => {
      beforeEach(() => {
        createComponent({ decision: buildMockDecision({ noteUrl: null, sourceLink: null }) });
      });

      it('is not rendered', () => {
        expect(findSourceLink().exists()).toBe(false);
      });
    });
  });

  describe('copy link action', () => {
    describe('when the work item URL is known', () => {
      beforeEach(() => {
        createComponent();
      });

      it('copies a link that reopens the panel on this decision', () => {
        expect(findCopyLinkAction().attributes('data-clipboard-text')).toBe(
          `${WORK_ITEM_URL}?show=decision-log#decision_1`,
        );
      });

      it('confirms the copy to the reader', () => {
        findCopyLinkAction().vm.$emit('action');

        expect(toast).toHaveBeenCalledWith('Link copied to clipboard.');
      });
    });

    describe('when the work item URL is missing', () => {
      beforeEach(() => {
        createComponent({ workItemWebUrl: '' });
      });

      it('offers nothing to copy, rather than a link to the wrong page', () => {
        expect(findActionsDropdown().exists()).toBe(false);
        expect(findCopyLinkAction().exists()).toBe(false);
      });
    });
  });

  describe('when the decision is active', () => {
    beforeEach(() => {
      createComponent();
    });

    it('gives the card the same surface a comment has', () => {
      expect(findCard().classes()).toContain('gl-bg-section');
      expect(findCard().classes()).not.toContain('gl-bg-disabled');
    });

    it('leaves the decision text at full strength', () => {
      expect(findAnswer().classes()).not.toContain('gl-text-subtle');
    });
  });

  describe('when the decision is archived', () => {
    beforeEach(() => {
      createComponent({ decision: buildMockDecision({ state: 'ARCHIVED' }) });
    });

    it('badges the card as archived', () => {
      expect(findArchivedBadge().text()).toBe('Archived');
    });

    it('drops the archive action, because the decision is already archived', () => {
      expect(findArchiveAction().exists()).toBe(false);
    });

    it('dims the card, so it reads as out of play next to the active ones', () => {
      expect(findCard().classes()).toContain('gl-bg-disabled');
      expect(findCard().classes()).not.toContain('gl-bg-section');
    });

    it('dims the decision text', () => {
      expect(findAnswer().classes()).toContain('gl-text-subtle');
    });
  });

  describe('when an archived decision settled several options', () => {
    beforeEach(() => {
      createComponent({
        decision: buildMockDecision({
          state: 'ARCHIVED',
          options: buildMockOptions([
            { ...unsettledOption, selected: true },
            { ...settledOption, selected: true },
          ]),
        }),
      });
    });

    it('dims every settled option, not just the first', () => {
      const dimmed = findAllAnswers().wrappers.filter((answer) =>
        answer.classes().includes('gl-text-subtle'),
      );

      expect(dimmed).toHaveLength(2);
    });
  });

  describe('the actions that change a decision', () => {
    beforeEach(() => {
      createComponent();
    });

    it('leaves the card unbadged while the decision is not archived', () => {
      expect(findArchivedBadge().exists()).toBe(false);
    });

    it('marks archiving as destructive', () => {
      expect(findArchiveAction().props('variant')).toBe('danger');
    });

    describe('when edit is selected', () => {
      beforeEach(() => {
        findEditAction().vm.$emit('action');
      });

      it('asks the panel to edit this decision', () => {
        expect(wrapper.emitted('edit')).toHaveLength(1);
      });
    });

    describe('when archive is selected', () => {
      beforeEach(() => {
        findArchiveAction().vm.$emit('action');
      });

      it('asks the panel to archive this decision', () => {
        expect(wrapper.emitted('archive')).toHaveLength(1);
      });
    });
  });

  describe('the anchor a copied link lands on', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names this decision', () => {
      expect(findCard().attributes('id')).toBe('decision_1');
    });

    it('leaves the card unhighlighted', () => {
      expect(findCard().classes()).not.toContain('is-target');
    });
  });

  describe('when the target anchor names this decision', () => {
    beforeEach(async () => {
      createComponent({ targetAnchor: 'decision_1' });
      await nextTick();
    });

    it('highlights the card', () => {
      expect(findCard().classes()).toContain('is-target');
    });

    it('scrolls the card into view', () => {
      expect(scrollIntoView).toHaveBeenCalled();
    });
  });

  describe('when the target anchor names another decision', () => {
    beforeEach(async () => {
      createComponent({ targetAnchor: 'decision_2' });
      await nextTick();
    });

    it('leaves the card unhighlighted', () => {
      expect(findCard().classes()).not.toContain('is-target');
    });

    it('does not scroll the card into view', () => {
      expect(scrollIntoView).not.toHaveBeenCalled();
    });
  });

  // Pasting a link while the panel is already open changes only the hash, so the panel hands down
  // a new anchor instead of the card being rebuilt.
  describe('when the target anchor moves onto this decision', () => {
    beforeEach(async () => {
      createComponent();
      await wrapper.setProps({ targetAnchor: 'decision_1' });
    });

    it('highlights the card', () => {
      expect(findCard().classes()).toContain('is-target');
    });
  });

  describe('when the target anchor moves off this decision', () => {
    beforeEach(async () => {
      createComponent({ targetAnchor: 'decision_1' });
      await wrapper.setProps({ targetAnchor: 'decision_2' });
    });

    it('drops the highlight', () => {
      expect(findCard().classes()).not.toContain('is-target');
    });
  });
});
