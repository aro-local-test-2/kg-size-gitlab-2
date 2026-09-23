import { GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import { helpPagePath } from '~/helpers/help_page_helper';
import WorkItemConfidenceScore from 'ee/work_items/components/ai_widget/work_item_confidence_score.vue';
import ConfidenceBar from 'ee/work_items/components/ai_widget/confidence_bar.vue';
import AiWidgetSegment from 'ee/vue_shared/components/work_items/ai_widget_segment.vue';
import { PLAN_CONFIDENCE_LEVELS } from 'ee/work_items/components/ai_widget/constants';

describe('WorkItemConfidenceScore', () => {
  let wrapper;

  const createComponent = ({ props = {}, mountFn = shallowMountExtended, stubs = {} } = {}) => {
    wrapper = mountFn(WorkItemConfidenceScore, {
      propsData: props,
      stubs: { AiWidgetSegment, ...stubs },
    });
  };

  const findPill = () => wrapper.findComponent(ConfidenceBar);
  const findHelpPopover = () => wrapper.findComponent(HelpPopover);
  const findHelpLink = () => wrapper.findComponent(GlLink);
  // We intentionally target by `role` rather than a `data-testid` here: the
  // point is to assert the element is exposed as the correct accessibility role
  // (an `img` with an aria-label) so it triggers the right behaviour for
  // assistive tech. A `data-testid` would not guarantee that.
  const findScoreGroup = () => wrapper.findByRole('img');
  const findScoreValue = () => wrapper.find('[data-testid="confidence-score-value"]');

  describe.each`
    scenario              | score  | confidenceLevel                  | label
    ${'zero'}             | ${0}   | ${PLAN_CONFIDENCE_LEVELS.LOW}    | ${'Low'}
    ${'low, upper bound'} | ${39}  | ${PLAN_CONFIDENCE_LEVELS.LOW}    | ${'Low'}
    ${'medium, lower'}    | ${40}  | ${PLAN_CONFIDENCE_LEVELS.MEDIUM} | ${'Medium'}
    ${'medium, upper'}    | ${79}  | ${PLAN_CONFIDENCE_LEVELS.MEDIUM} | ${'Medium'}
    ${'high, lower'}      | ${80}  | ${PLAN_CONFIDENCE_LEVELS.HIGH}   | ${'High'}
    ${'high, max'}        | ${100} | ${PLAN_CONFIDENCE_LEVELS.HIGH}   | ${'High'}
  `('when score is $scenario', ({ score, confidenceLevel, label }) => {
    beforeEach(() => {
      createComponent({ props: { score } });
    });

    it(`passes the "${label}" confidence level to the pill`, () => {
      expect(findPill().props('confidenceLevel')).toEqual(confidenceLevel);
    });

    it(`shows the "${label}" confidence label`, () => {
      expect(wrapper.text()).toContain(label);
    });

    it(`exposes "Confidence: ${label}" via aria-label`, () => {
      expect(findScoreGroup().attributes('aria-label')).toBe(`Confidence: ${label}`);
    });
  });

  describe('help popover', () => {
    beforeEach(() => {
      createComponent({ props: { score: 90 } });
    });

    it('uses the info icon since it provides additional information', () => {
      expect(findHelpPopover().props('icon')).toBe('information-o');
    });

    it('sets a clean aria-label without sprintf placeholders', () => {
      expect(findHelpPopover().props('ariaLabel')).toBe('What is the confidence score?');
      expect(findHelpPopover().props('ariaLabel')).not.toContain('linkStart');
    });

    it('explains how confidence is calculated', () => {
      const { content } = findHelpPopover().props('options');
      expect(content).toContain('Shows how ready this work item is for an agent to run');
      expect(content).toContain(
        'To raise the score, add more detail to the work item description and to the workplan steps',
      );
    });

    it('shows the title in the popover', () => {
      createComponent({
        props: { score: 90 },
        mountFn: mountExtended,
        stubs: {
          HelpPopover: stubComponent(HelpPopover, {
            template: '<div><slot name="title"></slot><slot></slot></div>',
          }),
          GlSprintf,
        },
      });

      expect(wrapper.text()).toContain('What is the confidence score?');
    });

    describe('score value', () => {
      const createMounted = (score) =>
        createComponent({
          props: { score },
          mountFn: mountExtended,
          stubs: {
            HelpPopover: stubComponent(HelpPopover, {
              template: '<div><slot name="title"></slot><slot></slot></div>',
            }),
            GlSprintf,
          },
        });

      it('renders the score out of 100', () => {
        createMounted(85);
        expect(findScoreValue().text()).toBe('Score: 85 / 100');
      });
    });

    it('links to the confidence score documentation', () => {
      createComponent({
        props: { score: 90 },
        mountFn: mountExtended,
        stubs: {
          HelpPopover: stubComponent(HelpPopover, {
            template: '<div><slot></slot></div>',
          }),
          GlSprintf,
        },
      });

      expect(findHelpLink().attributes('href')).toBe(
        helpPagePath('user/work_items/workplan.md', { anchor: 'confidence-score' }),
      );
    });
  });
});
