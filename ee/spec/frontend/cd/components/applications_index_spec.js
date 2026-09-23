import { GlButton, GlEmptyState, GlLoadingIcon } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { useLocalStorageSpy } from 'helpers/local_storage_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import ApplicationsIndex from 'ee/cd/components/applications_index.vue';
import ApplicationCard from 'ee/cd/components/application_card.vue';
import FilterBar from 'ee/cd/components/shared/filter_bar.vue';
import ManageAccessPanel from 'ee/cd/components/manage_access_panel.vue';
import NewApplicationPanel from 'ee/cd/components/new_application_panel.vue';
import { VIEW_GRID, VIEW_LIST, VIEW_MODE_KEY } from 'ee/cd/constants';
import cdApplicationsQuery from 'ee/cd/graphql/applications/cd_applications.query.graphql';

useLocalStorageSpy();

Vue.use(VueApollo);

describe('ApplicationsIndex', () => {
  let wrapper;

  const makeApplication = ({ id = '1', name = 'app-1' } = {}) => ({
    id,
    name,
    description: 'description',
    lastDeployedAt: 'last deployed at',
    services: { count: 1 },
  });

  const buildQueryResponse = (applications) => ({
    data: {
      organization: {
        id: 'gid://gitlab/Organizations::Organization/1',
        cdApplications: {
          nodes: applications,
        },
      },
    },
  });

  const defaultQueryHandler = jest.fn().mockResolvedValue(buildQueryResponse([makeApplication()]));

  const findPageHeading = () => wrapper.findComponent(PageHeading);
  const findNewApplicationButton = () => wrapper.findComponentByTestId('new-application-button');
  const findGridViewButton = () => wrapper.findComponentByTestId('grid-view-button');
  const findListViewButton = () => wrapper.findComponentByTestId('list-view-button');
  const findApplicationCards = () => wrapper.findAllComponents(ApplicationCard);
  const findFilterBar = () => wrapper.findComponent(FilterBar);
  const findManageAccessPanel = () => wrapper.findComponent(ManageAccessPanel);
  const findPanel = () => wrapper.findComponent(NewApplicationPanel);
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findEmptyState = () => wrapper.findComponent(GlEmptyState);

  const createComponent = ({ queryHandler = defaultQueryHandler } = {}) => {
    wrapper = shallowMountExtended(ApplicationsIndex, {
      apolloProvider: createMockApollo([[cdApplicationsQuery, queryHandler]]),
    });
  };

  it('renders the page heading', () => {
    createComponent();

    expect(findPageHeading().props('heading')).toBe('Applications');
  });

  it('renders the New application button', () => {
    createComponent();

    expect(findNewApplicationButton().text()).toBe('New application');
    expect(findNewApplicationButton().props('variant')).toBe('confirm');
  });

  it('renders the applications list', async () => {
    createComponent();
    await waitForPromises();

    expect(findApplicationCards()).toHaveLength(1);
  });

  describe('FilterBar search', () => {
    let queryHandler;

    beforeEach(async () => {
      queryHandler = jest.fn().mockResolvedValue(buildQueryResponse([makeApplication()]));
      createComponent({ queryHandler });
      await waitForPromises();
    });

    it('passes the correct search placeholder to FilterBar', () => {
      expect(findFilterBar().props('searchPlaceholder')).toBe('Search by name or description');
    });

    describe('on initial load', () => {
      it('queries with an empty search variable', () => {
        expect(queryHandler).toHaveBeenCalledWith({ search: '' });
      });
    });

    describe('when FilterBar emits search', () => {
      beforeEach(async () => {
        await findFilterBar().vm.$emit('search', 'my-app');
        await waitForPromises();
      });

      it('updates the searchTerm prop', () => {
        expect(findFilterBar().props('searchTerm')).toBe('my-app');
      });

      it('refetches the query with the search variable', () => {
        expect(queryHandler).toHaveBeenCalledWith({ search: 'my-app' });
      });
    });

    describe('when FilterBar emits search with surrounding whitespace', () => {
      beforeEach(async () => {
        await findFilterBar().vm.$emit('search', '  my-app  ');
        await waitForPromises();
      });

      it('trims whitespace from the search variable', () => {
        expect(queryHandler).toHaveBeenCalledWith({ search: 'my-app' });
      });
    });
  });

  describe('new application panel', () => {
    beforeEach(() => {
      createComponent();
    });

    it('is closed by default', () => {
      expect(findPanel().props('open')).toBe(false);
    });

    it('passes the organization id to the panel', async () => {
      await waitForPromises();

      expect(findPanel().props('organizationId')).toBe(
        'gid://gitlab/Organizations::Organization/1',
      );
    });

    it('opens when the "New application" button is clicked', async () => {
      await findNewApplicationButton().vm.$emit('click');

      expect(findPanel().props('open')).toBe(true);
    });

    it('closes when the panel emits close', async () => {
      await findNewApplicationButton().vm.$emit('click');

      expect(findPanel().props('open')).toBe(true);

      await findPanel().vm.$emit('close');

      expect(findPanel().props('open')).toBe(false);
    });

    it('refetches the applications when the panel emits create', async () => {
      const queryHandler = jest.fn().mockResolvedValue(buildQueryResponse([makeApplication()]));
      createComponent({ queryHandler });
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledTimes(1);

      await findPanel().vm.$emit('create');
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledTimes(2);
    });
  });

  describe('manage access panel', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('is closed by default', () => {
      expect(findManageAccessPanel().props('open')).toBe(false);
      expect(findManageAccessPanel().props('application')).toBe(null);
    });

    it('opens with the selected application when a card emits manage-access', async () => {
      const application = findApplicationCards().at(0).props('application');

      await findApplicationCards().at(0).vm.$emit('manage-access');

      expect(findManageAccessPanel().props('open')).toBe(true);
      expect(findManageAccessPanel().props('application')).toBe(application);
    });

    it('closes when the panel emits close', async () => {
      await findApplicationCards().at(0).vm.$emit('manage-access');

      expect(findManageAccessPanel().props('open')).toBe(true);

      await findManageAccessPanel().vm.$emit('close');

      expect(findManageAccessPanel().props('open')).toBe(false);
    });
  });

  describe('loading state', () => {
    it('shows a loading icon and hides the applications list while the query is pending', () => {
      createComponent();

      expect(findLoadingIcon().exists()).toBe(true);
      expect(findApplicationCards().exists()).toBe(false);
    });

    it('hides the loading icon once the query resolves', async () => {
      createComponent();
      await waitForPromises();

      expect(findLoadingIcon().exists()).toBe(false);
      expect(findApplicationCards().exists()).toBe(true);
    });
  });

  describe('empty states', () => {
    describe('when there are no applications and no filters are applied', () => {
      beforeEach(async () => {
        createComponent({ queryHandler: jest.fn().mockResolvedValue(buildQueryResponse([])) });
        await waitForPromises();
      });

      it('shows the "no applications yet" empty state instead of the applications list', () => {
        expect(findApplicationCards().exists()).toBe(false);
        expect(findEmptyState().props()).toMatchObject({
          illustrationName: 'empty-dashboard-md',
          title: 'No applications yet',
          description: 'Create applications to track them and deploy them to environments',
        });
      });

      it('opens the new application panel when the empty state action is clicked', async () => {
        await findEmptyState().findComponent(GlButton).vm.$emit('click');

        expect(findPanel().props('open')).toBe(true);
      });
    });

    describe('when a search term yields no results', () => {
      beforeEach(async () => {
        createComponent({ queryHandler: jest.fn().mockResolvedValue(buildQueryResponse([])) });
        await waitForPromises();

        await findFilterBar().vm.$emit('search', 'no-match');
        await waitForPromises();
      });

      it('shows the "no applications match your filters" empty state', () => {
        expect(findEmptyState().props()).toMatchObject({
          illustrationName: 'empty-search-md',
          title: 'No applications match your filters',
          description: 'To widen your search, change or remove filters above.',
        });
      });

      it('clears the search term when "Clear filters" is clicked', async () => {
        await findEmptyState().findComponent(GlButton).vm.$emit('click');

        expect(findFilterBar().props('searchTerm')).toBe('');
      });
    });
  });

  describe('view mode', () => {
    it('defaults to grid view when nothing is stored in localStorage', () => {
      createComponent();

      expect(findGridViewButton().props('selected')).toBe(true);
      expect(findListViewButton().props('selected')).toBe(false);
    });

    it('reads the persisted view mode from localStorage on load', () => {
      localStorage.setItem(VIEW_MODE_KEY, VIEW_LIST);
      createComponent();

      expect(findGridViewButton().props('selected')).toBe(false);
      expect(findListViewButton().props('selected')).toBe(true);
    });

    describe('when the list view button is clicked', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();

        await findListViewButton().vm.$emit('click');
      });

      it('selects the list view button and deselects the grid view button', () => {
        expect(findListViewButton().props('selected')).toBe(true);
        expect(findGridViewButton().props('selected')).toBe(false);
      });

      it('persists the list view to localStorage', () => {
        expect(localStorage.setItem).toHaveBeenCalledWith(VIEW_MODE_KEY, VIEW_LIST);
      });

      it('passes isGridView as false to each application card', () => {
        expect(findApplicationCards().at(0).props('isGridView')).toBe(false);
      });
    });

    describe('when the grid view button is clicked after switching to list view', () => {
      beforeEach(async () => {
        localStorage.setItem(VIEW_MODE_KEY, VIEW_LIST);
        createComponent();
        await waitForPromises();

        await findGridViewButton().vm.$emit('click');
      });

      it('selects the grid view button and deselects the list view button', () => {
        expect(findGridViewButton().props('selected')).toBe(true);
        expect(findListViewButton().props('selected')).toBe(false);
      });

      it('persists the grid view to localStorage', () => {
        expect(localStorage.setItem).toHaveBeenCalledWith(VIEW_MODE_KEY, VIEW_GRID);
      });

      it('passes isGridView as true to each application card', () => {
        expect(findApplicationCards().at(0).props('isGridView')).toBe(true);
      });
    });
  });
});
