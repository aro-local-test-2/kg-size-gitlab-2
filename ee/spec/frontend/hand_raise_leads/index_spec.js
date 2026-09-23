import handRaiseLeadEventHub from 'ee/hand_raise_leads/hand_raise_lead/event_hub';
import { initHandRaiseLead } from 'ee/hand_raise_leads/hand_raise_lead';
import initHandRaiseLeadModal from 'ee/hand_raise_leads/hand_raise_lead/init_hand_raise_lead_modal';
import initHandRaiseLeadButton from 'ee/hand_raise_leads/hand_raise_lead/init_hand_raise_lead_button';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import waitForPromises from 'helpers/wait_for_promises';

jest.mock('ee/hand_raise_leads/hand_raise_lead/init_hand_raise_lead_modal', () => ({
  __esModule: true,
  default: jest.fn(),
}));

jest.mock('ee/hand_raise_leads/hand_raise_lead/init_hand_raise_lead_button', () => ({
  __esModule: true,
  default: jest.fn(),
}));

describe('initHandRaiseLead', () => {
  // The real modal registers its own 'open-modal' listener from mounted(), which only
  // runs once the dynamically-imported chunk has resolved. This stands in for it.
  const modalListener = jest.fn();

  beforeEach(() => {
    initHandRaiseLeadModal.mockImplementation(() => {
      handRaiseLeadEventHub.$on('open-modal', modalListener);
    });
  });

  afterEach(() => {
    handRaiseLeadEventHub.$off('open-modal', modalListener);
    resetHTMLFixture();
  });

  describe('with a modal placeholder and a trigger on the page', () => {
    beforeEach(() => {
      setHTMLFixture(
        '<div class="js-hand-raise-lead-modal"></div><div class="js-hand-raise-lead-trigger"></div>',
      );
    });

    it('mounts the modal and the trigger', async () => {
      initHandRaiseLead();

      await waitForPromises();

      expect(initHandRaiseLeadModal).toHaveBeenCalled();
      expect(initHandRaiseLeadButton).toHaveBeenCalled();
    });

    it('replays a click that happened before the modal was listening', async () => {
      const options = { glmContent: 'billing-group' };

      initHandRaiseLead();

      // The trigger is clickable as soon as the page renders, which is before the
      // modal's chunk has resolved — nothing is listening yet.
      handRaiseLeadEventHub.$emit('open-modal', options);

      expect(modalListener).not.toHaveBeenCalled();

      await waitForPromises();

      expect(modalListener).toHaveBeenCalledTimes(1);
      expect(modalListener).toHaveBeenCalledWith(options);
    });

    it('does not open the modal when the trigger was never clicked', async () => {
      initHandRaiseLead();

      await waitForPromises();

      expect(modalListener).not.toHaveBeenCalled();
    });

    it('stops holding events once the modal is listening, so a later click arrives once', async () => {
      initHandRaiseLead();
      await waitForPromises();

      handRaiseLeadEventHub.$emit('open-modal', { glmContent: 'later' });

      expect(modalListener).toHaveBeenCalledTimes(1);
      expect(modalListener).toHaveBeenCalledWith({ glmContent: 'later' });
    });
  });

  describe('without a modal placeholder on the page', () => {
    beforeEach(() => {
      setHTMLFixture('<div class="js-hand-raise-lead-trigger"></div>');
    });

    it('does not mount the modal', async () => {
      initHandRaiseLead();

      await waitForPromises();

      expect(initHandRaiseLeadModal).not.toHaveBeenCalled();
      expect(initHandRaiseLeadButton).toHaveBeenCalled();
    });
  });
});
