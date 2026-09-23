import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { screen } from 'ee_jest/integration/helpers/test_helpers';
import {
  SEARCH_TERM,
  UNMATCHED_SEARCH_TERM,
  searchedCommitListResponse,
} from 'ee_jest/integration/commits/handlers';
import {
  apolloProvider,
  mountCommitListApp,
  findFilteredSearchInput,
  findActiveFilteredSearchInput,
  waitForCommitList,
} from './test_setup';

const searchedCommitTitle =
  searchedCommitListResponse.data.project.repository.commits.nodes[0].title;

// Focus the idle search input to activate it, then type into the active
// token segment input it swaps in, and submit with Enter.
const activateSearchInput = async () => {
  const idleInput = await waitForElement(findFilteredSearchInput);
  idleInput.focus();
  idleInput.click();

  return waitForElement(findActiveFilteredSearchInput);
};

const submitSearch = async (term) => {
  const input = await activateSearchInput();
  setInputValue(input, term);

  // Hand focus to the search button before clicking it: jsdom otherwise moves
  // focus to the document when the active segment unmounts on submit, and
  // GlFilteredSearch's blur handler crashes on a relatedTarget without classList.
  const searchButton = await waitForElement(() => screen.queryByTestId('search-button'));
  searchButton.focus();
  searchButton.click();
};

describe('Commit list filtered search', () => {
  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
    mountCommitListApp();
    await waitForCommitList();
  });

  describe('when activating the search input', () => {
    beforeEach(async () => {
      await activateSearchInput();
    });

    it('suggests the Author, Message, Committed after and Committed before tokens', async () => {
      await waitForAssertion(() => {
        const suggestions = [...document.querySelectorAll('.gl-filtered-search-suggestion-list li')]
          .map((el) => getText(el))
          // The list renders an empty separator item alongside the suggestions.
          .filter(Boolean);

        expect(suggestions).toEqual(['Author', 'Message', 'Committed after', 'Committed before']);
      });
    });
  });

  describe('when searching by commit message', () => {
    beforeEach(async () => {
      await submitSearch(SEARCH_TERM);
    });

    it('refetches with the query variable and shows only matching commits', async () => {
      await waitForAssertion(() => {
        expect(lastRequestVariables('getCommitList').query).toBe(SEARCH_TERM);
      });
      await waitForAssertion(() => {
        const text = getText(document.body);

        expect(text).toContain(searchedCommitTitle);
        expect(text).not.toContain('Feature added');
      });
    });
  });

  describe('when the search matches no commits', () => {
    beforeEach(async () => {
      await submitSearch(UNMATCHED_SEARCH_TERM);
    });

    it('shows the empty state', async () => {
      await waitForAssertion(() => {
        expect(getText(document.body)).toContain('No commits found');
      });
    });

    describe('when clearing the search', () => {
      beforeEach(async () => {
        await waitForAssertion(() => {
          expect(getText(document.body)).toContain('No commits found');
        });

        await waitAndClick(() => screen.queryByTestId('filtered-search-clear-button'));
        await waitForCommitList();
      });

      it('restores the commit list', () => {
        expect(getText(document.body)).toContain('Feature added');
      });
    });
  });
});
