import { waitFor } from '@testing-library/vue';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  PRODUCTION_TIER,
  SEARCH_TERM,
  UNMATCHED_SEARCH_TERM,
} from 'ee_jest/integration/cd/handlers';
import { expectListToShow, mountCdApp, readCardField } from './test_setup';

const PRODUCTION = 'production-eu';
const STAGING = 'staging-eu';
const DEVELOPMENT = 'dev-sandbox';

// The fixtures are capped at two per page; staging-eu is on the second.
const FIRST_PAGE = [PRODUCTION, DEVELOPMENT];
const ALL_ENVIRONMENTS = [...FIRST_PAGE, STAGING];

// What environment_card.vue renders when a field has no value.
const EMPTY_FIELD = '—';

describe('CD environments index', () => {
  const findHeadingDescription = () =>
    document.querySelector('[data-testid="page-heading-description"]');
  const findSearchInput = () => document.querySelector('[data-testid="filter-search"]');
  const findTierFilter = (tier) => document.querySelector(`[data-testid="filter-button-${tier}"]`);
  const findClearFiltersButton = () =>
    document.querySelector('[data-testid="clear-filters-button"]');
  const findLoadMoreButton = () => document.querySelector('[data-testid="load-more-button"]');

  beforeEach(() => {
    createPortalElement();

    mountCdApp();
  });

  it('renders a card for every environment on the first page', async () => {
    await expectListToShow(FIRST_PAGE);

    expect(getText(findHeadingDescription())).toBe('3 of 3 environments');
  });

  it('renders the deployment recorded against an environment', async () => {
    await expectListToShow(FIRST_PAGE);

    expect(readCardField(PRODUCTION, 'environment-card-release')).toBe('release-2026.08.1');
    expect(readCardField(PRODUCTION, 'environment-card-deployed-by')).toBe('cd-deployer');
    expect(readCardField(PRODUCTION, 'environment-card-apps')).toBe('2 apps');
  });

  it('leaves the deployment fields blank for an environment that was never deployed to', async () => {
    await expectListToShow(FIRST_PAGE);

    expect(readCardField(DEVELOPMENT, 'environment-card-release')).toBe(EMPTY_FIELD);
    expect(readCardField(DEVELOPMENT, 'environment-card-deployed-by')).toBe(EMPTY_FIELD);
    expect(readCardField(DEVELOPMENT, 'environment-card-apps')).toBe('0 apps');
  });

  it('names the cluster agent each environment is bound to', async () => {
    await expectListToShow(FIRST_PAGE);

    expect(readCardField(PRODUCTION, 'environment-card-cluster-agent')).toBe('production-cluster');
    expect(readCardField(DEVELOPMENT, 'environment-card-cluster-agent')).toBe(EMPTY_FIELD);
  });

  describe('when a tier is selected', () => {
    beforeEach(async () => {
      await expectListToShow(FIRST_PAGE);

      findTierFilter(PRODUCTION_TIER).click();
    });

    it('asks the API for that tier and shows only what it returns', async () => {
      await expectListToShow([PRODUCTION]);

      expect(lastRequestVariables('cdEnvironments')).toMatchObject({
        tier: PRODUCTION_TIER,
        search: '',
      });
    });

    it('keeps the unfiltered total alongside the filtered count', async () => {
      await waitFor(() => {
        expect(getText(findHeadingDescription())).toBe('1 of 3 environments');
      });
    });
  });

  describe('when a search term is entered', () => {
    beforeEach(async () => {
      await expectListToShow(FIRST_PAGE);

      setInputValue(findSearchInput(), SEARCH_TERM);
    });

    it('asks the API for that term and shows only what it returns', async () => {
      await expectListToShow([PRODUCTION]);

      expect(lastRequestVariables('cdEnvironments')).toMatchObject({
        search: SEARCH_TERM,
        tier: null,
      });
    });
  });

  describe('when the search matches nothing', () => {
    beforeEach(async () => {
      await expectListToShow(FIRST_PAGE);

      setInputValue(findSearchInput(), UNMATCHED_SEARCH_TERM);
    });

    it('replaces the list with the no-results empty state', async () => {
      await waitForElement(findClearFiltersButton);

      await expectListToShow([]);
      expect(getText(document.body)).toContain('No environments match your filters');
    });

    it('restores the full list when the filters are cleared', async () => {
      await waitAndClick(findClearFiltersButton);

      await expectListToShow(FIRST_PAGE);
    });
  });

  describe('when there is another page of environments', () => {
    beforeEach(async () => {
      await expectListToShow(FIRST_PAGE);
    });

    it('appends the next page to the environments already on screen', async () => {
      await waitAndClick(findLoadMoreButton);

      await expectListToShow(ALL_ENVIRONMENTS);
    });

    it('asks for the page after the cursor the API returned', async () => {
      await waitAndClick(findLoadMoreButton);

      await waitForAssertion(() => {
        expect(lastRequestVariables('cdEnvironments')).toMatchObject({
          after: expect.any(String),
          search: '',
          tier: null,
        });
      });
    });

    it('renders the appended environment from the second page in full', async () => {
      await waitAndClick(findLoadMoreButton);
      await expectListToShow(ALL_ENVIRONMENTS);

      expect(readCardField(STAGING, 'environment-card-cluster-agent')).toBe('staging-cluster');
      expect(readCardField(STAGING, 'environment-card-apps')).toBe('1 app');
    });

    it('stops offering more once the last page is loaded', async () => {
      await waitAndClick(findLoadMoreButton);
      await expectListToShow(ALL_ENVIRONMENTS);

      expect(findLoadMoreButton()).toBe(null);
    });
  });
});
