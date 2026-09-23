export const initReviewOnPushCheckbox = () => {
  const autoReviewCheckbox = document.querySelector('.js-auto-duo-code-review');
  const reviewOnPushCheckbox = document.querySelector('.js-auto-duo-code-review-on-push');

  if (!autoReviewCheckbox || !reviewOnPushCheckbox) {
    return;
  }

  // Both render disabled when the feature is unavailable. A disabled parent can still be
  // checked, so enabling the child from its checked state would undo that.
  if (autoReviewCheckbox.disabled) {
    return;
  }

  // Rails pairs the checkbox with a hidden input holding the unchecked value. Disabling
  // only the checkbox would still submit that hidden value and overwrite the setting.
  const uncheckedValueInput = reviewOnPushCheckbox.previousElementSibling;

  const setDisabled = (disabled) => {
    reviewOnPushCheckbox.disabled = disabled;

    if (uncheckedValueInput?.type === 'hidden') {
      uncheckedValueInput.disabled = disabled;
    }
  };

  setDisabled(!autoReviewCheckbox.checked);

  autoReviewCheckbox.addEventListener('change', () => {
    if (autoReviewCheckbox.checked) {
      reviewOnPushCheckbox.checked = true;
    }

    setDisabled(!autoReviewCheckbox.checked);
  });
};
