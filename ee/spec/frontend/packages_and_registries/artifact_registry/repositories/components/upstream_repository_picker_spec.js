import { GlAlert, GlToken, GlTokenSelector } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import getUpstreamRepositoryCandidatesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_upstream_repository_candidates.query.graphql';
import UpstreamRepositoryPicker from 'ee/packages_and_registries/artifact_registry/repositories/components/upstream_repository_picker.vue';
import {
  ORGANIZATION_GID,
  mockEmptyUpstreamRepositoryCandidatePage,
  mockUpstreamRepositoryCandidatePages,
  mockUpstreamRepositoryCandidatesResponse,
} from '../../mock_data';

Vue.use(VueApollo);

const [FIRST_PAGE, SECOND_PAGE] = mockUpstreamRepositoryCandidatePages;

const FIRST_PAGE_END_CURSOR = 'Y2FuZGlkYXRlcy1wYWdlLTE=';

const SECOND_PAGE_END_CURSOR = 'Y2FuZGlkYXRlcy1wYWdlLTI=';

const LISTED_UPSTREAM_ID = 'd1000000-0000-4000-8000-000000000001';

const withoutNextPage = (page) => ({
  ...page,
  pageInfo: { ...page.pageInfo, hasNextPage: false, endCursor: null },
});

const withNextPage = (page) => ({
  ...page,
  pageInfo: { ...page.pageInfo, hasNextPage: true, endCursor: SECOND_PAGE_END_CURSOR },
});

const pageOf = (nodes) => ({ ...mockEmptyUpstreamRepositoryCandidatePage, nodes });

describe('ArtifactRegistryUpstreamRepositoryPicker', () => {
  let wrapper;
  let handler;

  const candidatesHandler = (...pages) =>
    pages.reduce(
      (mock, page) => mock.mockResolvedValueOnce(mockUpstreamRepositoryCandidatesResponse(page)),
      jest.fn(),
    );

  const pendingCandidatesHandler = () => jest.fn().mockReturnValue(new Promise(() => {}));

  const findPicker = () => wrapper.findByTestId('upstream-repository-picker');
  const findTokenSelector = () => wrapper.findComponent(GlTokenSelector);
  const findSearchInput = () => findTokenSelector().find('input[type="text"]');
  const findSentinel = () => wrapper.findComponentByTestId('picker-sentinel');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findConfirm = () => wrapper.findComponentByTestId('picker-confirm');
  const findCancel = () => wrapper.findComponentByTestId('picker-cancel');
  const findCapError = () => wrapper.findByTestId('picker-cap-error');
  const findNoAttachable = () => wrapper.findByTestId('picker-no-attachable');
  const findNoMatch = () => wrapper.findByTestId('picker-no-match');
  const findAnnouncement = () => wrapper.findByTestId('upstream-repository-picker-announcement');

  const textsOf = (testId) => wrapper.findAllByTestId(testId).wrappers.map((node) => node.text());

  const candidateNames = () => textsOf('candidate-name');
  const candidateUrls = () => textsOf('candidate-url');
  const candidateKinds = () => textsOf('candidate-kind');
  const chipNames = () => wrapper.findAllComponents(GlToken).wrappers.map((chip) => chip.text());

  const queryVariables = (overrides = {}) => ({
    organizationId: ORGANIZATION_GID,
    kinds: ['HOSTED', 'REMOTE'],
    formats: ['MAVEN'],
    first: 20,
    ...overrides,
  });

  const createComponent = async ({
    props = {},
    candidates = candidatesHandler(FIRST_PAGE),
  } = {}) => {
    handler = candidates;

    wrapper = mountExtended(UpstreamRepositoryPicker, {
      apolloProvider: createMockApollo([[getUpstreamRepositoryCandidatesQuery, handler]]),
      provide: { organizationGid: ORGANIZATION_GID },
      propsData: {
        format: 'MAVEN',
        excludedIds: [],
        listSize: 0,
        ...props,
      },
      attachTo: document.body,
    });

    await waitForPromises();
  };

  const search = async (text) => {
    await findSearchInput().setValue(text);
    await waitForPromises();
  };

  const selectCandidate = async (name) => {
    await wrapper
      .findAllByTestId('candidate-name')
      .at(candidateNames().indexOf(name))
      .trigger('click');
    await waitForPromises();
  };

  const removeToken = async (name) => {
    wrapper
      .findAllComponents(GlToken)
      .wrappers.find((chip) => chip.text() === name)
      .vm.$emit('close');
    await waitForPromises();
  };

  const loadNextPage = async () => {
    findSentinel().vm.$emit('appear');
    await waitForPromises();
  };

  describe('the request it takes to the server', () => {
    it('renders itself', async () => {
      await createComponent();

      expect(findPicker().exists()).toBe(true);
    });

    describe.each([
      ['MAVEN', ['MAVEN']],
      ['NPM', ['NPM']],
      ['DOCKER', ['DOCKER', 'OCI']],
      ['OCI', ['DOCKER', 'OCI']],
    ])('when the virtual repository is %s', (format, formats) => {
      beforeEach(async () => {
        await createComponent({ props: { format } });
      });

      it('leaves the kind and the format to the server, asking for that family alone', () => {
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler).toHaveBeenCalledWith(queryVariables({ formats }));
      });
    });
  });

  describe('the repositories it offers', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('offers every repository the server returned, in the order the page held them', () => {
      expect(candidateNames()).toEqual(['platform-libs', 'maven-central', 'maven-central-proxy']);
    });

    it('renders the URL of a remote repository, and none where there is none', () => {
      expect(candidateUrls()).toEqual([
        'https://repo1.maven.org/maven2',
        'https://repo.maven.apache.org/maven2',
      ]);
    });

    it('names the kind of each repository as a word', () => {
      expect(candidateKinds()).toEqual(['Hosted', 'Remote', 'Remote']);
    });
  });

  describe('when the server returns a row the query asked it to withhold', () => {
    beforeEach(async () => {
      await createComponent({
        candidates: candidatesHandler(
          pageOf([
            {
              __typename: 'ArtifactRegistryRepository',
              id: 'c1000000-0000-4000-8000-000000000005',
              name: 'all-maven',
              format: 'NPM',
              kind: 'VIRTUAL',
              sizeBytes: null,
              settings: null,
            },
          ]),
        ),
      });
    });

    it('offers it anyway, because it filters neither kind nor format a second time', () => {
      expect(candidateNames()).toEqual(['all-maven']);
    });
  });

  describe('when a repository is already in the list', () => {
    beforeEach(async () => {
      await createComponent({ props: { excludedIds: [LISTED_UPSTREAM_ID] } });
    });

    it('offers it no second time', () => {
      expect(candidateNames()).toEqual(['platform-libs', 'maven-central']);
    });
  });

  describe('searching', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('narrows the list by name', async () => {
      await search('platform');

      expect(candidateNames()).toEqual(['platform-libs']);
    });

    it('narrows the list by URL', async () => {
      await search('repo1');

      expect(candidateNames()).toEqual(['maven-central']);
    });

    it('ignores the case of the search', async () => {
      await search('PLATFORM');

      expect(candidateNames()).toEqual(['platform-libs']);
    });

    it('ignores space around the search', async () => {
      await search('  platform  ');

      expect(candidateNames()).toEqual(['platform-libs']);
    });

    it('offers every repository again once the search is cleared', async () => {
      await search('platform');
      await search('');

      expect(candidateNames()).toEqual(['platform-libs', 'maven-central', 'maven-central-proxy']);
    });

    it('sends no request, because the search is the picker’s own', async () => {
      await search('platform');

      expect(handler).toHaveBeenCalledTimes(1);
    });
  });

  describe('when a page arrives while a search is active', () => {
    beforeEach(async () => {
      await createComponent({ candidates: candidatesHandler(FIRST_PAGE, SECOND_PAGE) });
      await search('spring');
    });

    it('matches nothing in the pages loaded so far', () => {
      expect(candidateNames()).toEqual([]);
    });

    it('narrows the arriving page by the same search', async () => {
      await loadNextPage();

      expect(candidateNames()).toEqual(['spring-releases']);
    });
  });

  describe('when the search matches nothing and pages remain', () => {
    beforeEach(async () => {
      await createComponent();
      await search('zzz');
    });

    it('says that scrolling loads and searches more', () => {
      expect(findNoMatch().text()).toBe(
        '0 loaded repositories match. Keep scrolling to load and search more.',
      );
    });

    it('renders no line about there being nothing to attach', () => {
      expect(findNoAttachable().exists()).toBe(false);
    });
  });

  describe('when the search matches nothing and no page remains', () => {
    beforeEach(async () => {
      await createComponent({ candidates: candidatesHandler(withoutNextPage(FIRST_PAGE)) });
      await search('zzz');
    });

    it('says the search matched nothing', () => {
      expect(findNoMatch().text()).toBe('No repositories match your search.');
    });
  });

  describe.each([
    [
      'MAVEN',
      'No Maven repositories are available to add. Create a hosted or remote repository first.',
    ],
    [
      'DOCKER',
      'No Docker repositories are available to add. Create a hosted or remote repository first.',
    ],
    [
      'NPM',
      'No npm repositories are available to add. Create a hosted or remote repository first.',
    ],
    [
      'OCI',
      'No OCI repositories are available to add. Create a hosted or remote repository first.',
    ],
  ])('when a %s virtual repository has nothing to attach', (format, expected) => {
    beforeEach(async () => {
      await createComponent({
        props: { format },
        candidates: candidatesHandler(mockEmptyUpstreamRepositoryCandidatePage),
      });
    });

    it('names the format and says what to create first', () => {
      expect(findNoAttachable().text()).toBe(expected);
    });

    it('renders no line about a search, because there is no search', () => {
      expect(findNoMatch().exists()).toBe(false);
    });
  });

  describe('while the first page is still on its way', () => {
    beforeEach(async () => {
      await createComponent({ candidates: pendingCandidatesHandler() });
    });

    it('holds back the line about there being nothing to attach', () => {
      expect(findNoAttachable().exists()).toBe(false);
    });

    it('offers nothing yet', () => {
      expect(candidateNames()).toEqual([]);
    });
  });

  describe('when the sentinel appears', () => {
    beforeEach(async () => {
      await createComponent({ candidates: candidatesHandler(FIRST_PAGE, SECOND_PAGE) });
      await loadNextPage();
    });

    it('asks for the page after the cursor the last page carried', () => {
      expect(handler).toHaveBeenCalledTimes(2);
      expect(handler).toHaveBeenLastCalledWith(queryVariables({ after: FIRST_PAGE_END_CURSOR }));
    });

    it('offers the repositories it brought back, after the ones it held', () => {
      expect(candidateNames()).toEqual([
        'platform-libs',
        'maven-central',
        'maven-central-proxy',
        'spring-releases',
      ]);
    });

    it('renders no sentinel once the last page has arrived', () => {
      expect(findSentinel().exists()).toBe(false);
    });

    it('counts the repositories it now holds', () => {
      expect(findAnnouncement().text()).toBe('4 repositories loaded.');
    });
  });

  describe('when every repository on an arriving page is already listed', () => {
    beforeEach(async () => {
      await createComponent({
        props: { excludedIds: ['c1000000-0000-4000-8000-000000000004'] },
        candidates: candidatesHandler(FIRST_PAGE, withNextPage(SECOND_PAGE)),
      });
      await loadNextPage();
    });

    it('asks for no further page of its own accord, leaving that to the sentinel', () => {
      expect(handler).toHaveBeenCalledTimes(2);
    });

    it('leaves the announcement as the page before it left it', () => {
      expect(findAnnouncement().text()).toBe('3 repositories loaded.');
    });

    it('keeps the sentinel, because a page still remains', () => {
      expect(findSentinel().exists()).toBe(true);
    });
  });

  describe('when the first page is the last one', () => {
    beforeEach(async () => {
      await createComponent({ candidates: candidatesHandler(withoutNextPage(FIRST_PAGE)) });
    });

    it('renders no sentinel', () => {
      expect(findSentinel().exists()).toBe(false);
    });
  });

  describe('picking repositories', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('holds each pick as a chip, in the order they were picked', async () => {
      await selectCandidate('maven-central');
      await selectCandidate('platform-libs');

      expect(chipNames()).toEqual(['maven-central', 'platform-libs']);
    });

    it('drops a picked repository from the rows left to pick', async () => {
      await selectCandidate('maven-central');

      expect(candidateNames()).toEqual(['platform-libs', 'maven-central-proxy']);
    });
  });

  describe('the actions beneath the list', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('labels them with the verb each one carries out, sized to sit inside the card', () => {
      expect(findConfirm().text()).toBe('Add');
      expect(findConfirm().props('size')).toBe('small');
      expect(findCancel().text()).toBe('Cancel');
      expect(findCancel().props('size')).toBe('small');
    });

    it('marks the add action as the one that confirms', () => {
      expect(findConfirm().props('variant')).toBe('confirm');
    });

    it('disables the add action until something is picked', () => {
      expect(findConfirm().props('disabled')).toBe(true);
    });

    it('enables the add action once something is picked', async () => {
      await selectCandidate('platform-libs');

      expect(findConfirm().props('disabled')).toBe(false);
    });
  });

  describe('confirming the picks', () => {
    beforeEach(async () => {
      await createComponent();
      await selectCandidate('maven-central');
      await selectCandidate('platform-libs');
      await findConfirm().trigger('click');
    });

    it('hands its parent the picked rows in chip order', () => {
      expect(wrapper.emitted('confirm')).toEqual([
        [
          [
            {
              id: 'c1000000-0000-4000-8000-000000000002',
              name: 'maven-central',
              kind: 'REMOTE',
              sizeBytes: null,
              url: 'https://repo1.maven.org/maven2',
            },
            {
              id: 'c1000000-0000-4000-8000-000000000001',
              name: 'platform-libs',
              kind: 'HOSTED',
              sizeBytes: '4096',
              url: null,
            },
          ],
        ],
      ]);
    });

    it('closes nothing itself, leaving that to its parent', () => {
      expect(wrapper.emitted('close')).toBeUndefined();
    });

    it('sends no request of its own', () => {
      expect(handler).toHaveBeenCalledTimes(1);
    });
  });

  describe('when the picks would take the list past its cap', () => {
    beforeEach(async () => {
      await createComponent({ props: { listSize: 18 } });
      await selectCandidate('platform-libs');
      await selectCandidate('maven-central');
      await selectCandidate('maven-central-proxy');
    });

    it('disables the add action and says how many picks to remove', () => {
      expect(findConfirm().props('disabled')).toBe(true);
      expect(findCapError().text()).toBe(
        'Remove 1 repository from the selection to stay within the maximum of 20.',
      );
    });

    it('describes the disabled add action by the message', () => {
      expect(findConfirm().attributes('aria-describedby')).toBe(findCapError().attributes('id'));
    });

    it('marks the search field invalid and describes it by the message', () => {
      const describedBy = findSearchInput().attributes('aria-describedby');

      expect(findSearchInput().attributes('aria-invalid')).toBe('true');
      expect(wrapper.find(`#${describedBy}`).text()).toBe(
        'Remove 1 repository from the selection to stay within the maximum of 20.',
      );
    });

    it('keeps naming the search field while it is marked invalid', () => {
      expect(wrapper.findByRole('combobox', { name: 'Search by name or URL' }).exists()).toBe(true);
    });

    it('confirms nothing while the selection is over the cap', async () => {
      await findConfirm().trigger('click');

      expect(wrapper.emitted('confirm')).toBeUndefined();
    });

    it('enables the add action again once enough picks are removed', async () => {
      await removeToken('maven-central-proxy');

      expect(findConfirm().props('disabled')).toBe(false);
      expect(findCapError().exists()).toBe(false);
      expect(findConfirm().attributes('aria-describedby')).toBeUndefined();
    });

    it('clears the invalid state of the search field once enough picks are removed', async () => {
      await removeToken('maven-central-proxy');

      expect(findSearchInput().attributes('aria-invalid')).toBeUndefined();
      expect(findSearchInput().attributes('aria-describedby')).toBeUndefined();
    });

    it('pluralizes the picks to remove', async () => {
      await createComponent({ props: { listSize: 19 } });
      await selectCandidate('platform-libs');
      await selectCandidate('maven-central');
      await selectCandidate('maven-central-proxy');

      expect(findCapError().text()).toBe(
        'Remove 2 repositories from the selection to stay within the maximum of 20.',
      );
    });
  });

  describe('when the picks fill the list exactly to its cap', () => {
    beforeEach(async () => {
      await createComponent({ props: { listSize: 18 } });
      await selectCandidate('platform-libs');
      await selectCandidate('maven-central');
    });

    it('keeps the add action enabled with no message', () => {
      expect(findConfirm().props('disabled')).toBe(false);
      expect(findCapError().exists()).toBe(false);
    });
  });

  describe('cancelling', () => {
    beforeEach(async () => {
      await createComponent();
      await selectCandidate('platform-libs');
      await findCancel().trigger('click');
    });

    it('asks its parent to close it', () => {
      expect(wrapper.emitted('close')).toEqual([[]]);
    });

    it('hands over nothing it had picked', () => {
      expect(wrapper.emitted('confirm')).toBeUndefined();
    });
  });

  describe('the search field', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('holds the focus, so typing narrows the list at once', () => {
      expect(document.activeElement).toBe(findSearchInput().element);
    });

    it('names itself to a screen reader and to the eye', () => {
      expect(wrapper.findByRole('combobox', { name: 'Search by name or URL' }).exists()).toBe(true);
      expect(findSearchInput().attributes('placeholder')).toBe('Search by name or URL');
    });

    it('carries no invalid state while the selection sits within the cap', () => {
      expect(findSearchInput().attributes('aria-invalid')).toBeUndefined();
      expect(findSearchInput().attributes('aria-describedby')).toBeUndefined();
    });
  });

  describe('the announcement', () => {
    it('sits in a polite, atomic region that is read out but not shown', async () => {
      await createComponent();

      expect(findAnnouncement().classes()).toContain('gl-sr-only');
      expect(findAnnouncement().attributes('aria-live')).toBe('polite');
      expect(findAnnouncement().attributes('aria-atomic')).toBe('true');
    });

    it('counts the repositories a page brought', async () => {
      await createComponent();

      expect(findAnnouncement().text()).toBe('3 repositories loaded.');
    });

    it('counts a single repository in the singular', async () => {
      await createComponent({ candidates: candidatesHandler(SECOND_PAGE) });

      expect(findAnnouncement().text()).toBe('1 repository loaded.');
    });

    it('says nothing when a page brought nothing', async () => {
      await createComponent({
        candidates: candidatesHandler(mockEmptyUpstreamRepositoryCandidatePage),
      });

      expect(findAnnouncement().text()).toBe('');
    });

    it.each([
      ['maven', '2 repositories match.'],
      ['platform', '1 repository matches.'],
      ['zzz', '0 repositories match.'],
    ])('counts the matches of the search %p', async (text, expected) => {
      await createComponent();
      await search(text);

      expect(findAnnouncement().text()).toBe(expected);
    });

    it('counts one pick against the cap', async () => {
      await createComponent();
      await selectCandidate('platform-libs');

      expect(findAnnouncement().text()).toBe('1 repository selected. The list will hold 1 of 20.');
    });

    it('counts several picks against the cap', async () => {
      await createComponent();
      await selectCandidate('platform-libs');
      await selectCandidate('maven-central');

      expect(findAnnouncement().text()).toBe(
        '2 repositories selected. The list will hold 2 of 20.',
      );
    });

    it('counts the picks against the cap even where they would pass it', async () => {
      await createComponent({ props: { listSize: 18 } });
      await selectCandidate('platform-libs');
      await selectCandidate('maven-central');
      await selectCandidate('maven-central-proxy');

      expect(findAnnouncement().text()).toBe(
        '3 repositories selected. The list will hold 21 of 20.',
      );
    });
  });

  describe('when the read fails', () => {
    beforeEach(async () => {
      await createComponent({ candidates: jest.fn().mockRejectedValue(new Error('Unavailable')) });
    });

    it('says the repositories could not be loaded', () => {
      expect(findAlert().text()).toBe('Failed to load repositories.');
    });

    it('renders the failure as an error the user cannot wave away', () => {
      expect(findAlert().props('variant')).toBe('danger');
      expect(findAlert().props('dismissible')).toBe(false);
    });
  });

  describe('when the read succeeds', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('renders no failure', () => {
      expect(findAlert().exists()).toBe(false);
    });
  });
});
