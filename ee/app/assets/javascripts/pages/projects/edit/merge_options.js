export const initMergeOptionSettings = () => {
  const mergePipelinesCheckbox = document.querySelector('.js-merge-options-merge-pipelines');
  const mergeTrainsCheckbox = document.querySelector('.js-merge-options-merge-trains');

  if (!mergePipelinesCheckbox || !mergeTrainsCheckbox) {
    return;
  }

  mergeTrainsCheckbox.disabled = !mergePipelinesCheckbox.checked;

  mergePipelinesCheckbox.addEventListener('change', () => {
    if (!mergePipelinesCheckbox.checked) {
      mergeTrainsCheckbox.checked = false;
    }
    mergeTrainsCheckbox.disabled = !mergePipelinesCheckbox.checked;
  });
};
