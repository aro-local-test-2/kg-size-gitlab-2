import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import { initReviewOnPushCheckbox } from 'ee/duo_code_review/init_review_on_push_checkbox';

describe('initReviewOnPushCheckbox', () => {
  const findAutoReview = () => document.querySelector('.js-auto-duo-code-review');
  const findReviewOnPush = () => document.querySelector('.js-auto-duo-code-review-on-push');
  const findUncheckedValueInput = () => document.querySelector('input[type="hidden"]');

  const setUpFixture = ({ autoReviewChecked, reviewOnPushChecked = true, disabled = false }) => {
    const disabledAttr = disabled ? 'disabled' : '';

    setHTMLFixture(`
      <input type="checkbox" class="js-auto-duo-code-review" ${
        autoReviewChecked ? 'checked' : ''
      } ${disabledAttr} />
      <input type="hidden" name="auto_duo_code_review_on_push_enabled" value="0" ${disabledAttr} />
      <input type="checkbox" class="js-auto-duo-code-review-on-push" ${
        reviewOnPushChecked ? 'checked' : ''
      } ${disabledAttr} />
    `);
  };

  const toggleAutoReview = (checked) => {
    findAutoReview().checked = checked;
    findAutoReview().dispatchEvent(new Event('change'));
  };

  afterEach(() => {
    resetHTMLFixture();
  });

  it('disables review on push while automatic review is off, without changing its value', () => {
    setUpFixture({ autoReviewChecked: false });

    initReviewOnPushCheckbox();

    expect(findReviewOnPush().disabled).toBe(true);
    expect(findReviewOnPush().checked).toBe(true);
  });

  it('disables the unchecked value input so that a disabled setting is not submitted', () => {
    setUpFixture({ autoReviewChecked: true });

    initReviewOnPushCheckbox();

    expect(findUncheckedValueInput().disabled).toBe(false);

    toggleAutoReview(false);

    expect(findUncheckedValueInput().disabled).toBe(true);

    toggleAutoReview(true);

    expect(findUncheckedValueInput().disabled).toBe(false);
  });

  it('leaves review on push alone while automatic review is on', () => {
    setUpFixture({ autoReviewChecked: true, reviewOnPushChecked: false });

    initReviewOnPushCheckbox();

    expect(findReviewOnPush().disabled).toBe(false);
    expect(findReviewOnPush().checked).toBe(false);
  });

  it('turns review on push on when automatic review is turned on', () => {
    setUpFixture({ autoReviewChecked: false, reviewOnPushChecked: false });

    initReviewOnPushCheckbox();
    toggleAutoReview(true);

    expect(findReviewOnPush().disabled).toBe(false);
    expect(findReviewOnPush().checked).toBe(true);
  });

  it('disables review on push when automatic review is turned off', () => {
    setUpFixture({ autoReviewChecked: true });

    initReviewOnPushCheckbox();
    toggleAutoReview(false);

    expect(findReviewOnPush().disabled).toBe(true);
  });

  it('leaves review on push disabled when the feature is unavailable', () => {
    setUpFixture({ autoReviewChecked: true, disabled: true });

    initReviewOnPushCheckbox();

    expect(findReviewOnPush().disabled).toBe(true);
    expect(findUncheckedValueInput().disabled).toBe(true);
  });
});
