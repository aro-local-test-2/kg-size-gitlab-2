import { initMergeOptionSettings } from 'ee/pages/projects/edit/merge_options';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';

describe('initMergeOptionSettings', () => {
  const findMergePipelinesCheckbox = () =>
    document.querySelector('.js-merge-options-merge-pipelines');
  const findMergeTrainsCheckbox = () => document.querySelector('.js-merge-options-merge-trains');

  const createFixture = ({ mergePipelinesEnabled, mergeTrainsEnabled, mergeTrainsDisabled }) => {
    setHTMLFixture(`
      <fieldset id="project-merge-options">
        <input type="checkbox" class="js-merge-options-merge-pipelines" ${
          mergePipelinesEnabled ? 'checked' : ''
        } />
        <input type="checkbox" class="js-merge-options-merge-trains" ${
          mergeTrainsEnabled ? 'checked' : ''
        } ${mergeTrainsDisabled ? 'disabled' : ''} />
      </fieldset>
    `);
  };

  afterEach(() => {
    resetHTMLFixture();
  });

  describe.each`
    mergePipelinesEnabled | mergeTrainsEnabled | expectedDisabled
    ${true}               | ${true}            | ${false}
    ${true}               | ${false}           | ${false}
    ${false}              | ${true}            | ${true}
    ${false}              | ${false}           | ${true}
  `(
    'with mergePipelinesEnabled=$mergePipelinesEnabled and mergeTrainsEnabled=$mergeTrainsEnabled',
    ({ mergePipelinesEnabled, mergeTrainsEnabled, expectedDisabled }) => {
      it(`sets the merge trains checkbox disabled state to ${expectedDisabled}`, () => {
        // Start from the opposite disabled state so a no-op init fails
        createFixture({
          mergePipelinesEnabled,
          mergeTrainsEnabled,
          mergeTrainsDisabled: !expectedDisabled,
        });

        initMergeOptionSettings();

        expect(findMergeTrainsCheckbox().disabled).toBe(expectedDisabled);
        expect(findMergeTrainsCheckbox().checked).toBe(mergeTrainsEnabled);
      });
    },
  );

  it('disables and unchecks merge trains when merged results pipelines is unchecked', () => {
    createFixture({ mergePipelinesEnabled: true, mergeTrainsEnabled: true });

    initMergeOptionSettings();
    findMergePipelinesCheckbox().click();

    expect(findMergeTrainsCheckbox().disabled).toBe(true);
    expect(findMergeTrainsCheckbox().checked).toBe(false);
  });

  it('enables merge trains when merged results pipelines is checked', () => {
    createFixture({
      mergePipelinesEnabled: false,
      mergeTrainsEnabled: false,
      mergeTrainsDisabled: true,
    });

    initMergeOptionSettings();
    findMergePipelinesCheckbox().click();

    expect(findMergeTrainsCheckbox().disabled).toBe(false);
    expect(findMergeTrainsCheckbox().checked).toBe(false);
  });

  it('does nothing when the merge trains checkbox is absent', () => {
    setHTMLFixture(`
      <fieldset id="project-merge-options">
        <input type="checkbox" class="js-merge-options-merge-pipelines" checked />
      </fieldset>
    `);

    expect(() => initMergeOptionSettings()).not.toThrow();
  });
});
