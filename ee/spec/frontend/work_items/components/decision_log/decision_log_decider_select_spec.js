import { GlCollapsibleListbox } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import usersSearchQuery from '~/graphql_shared/queries/workspace_autocomplete_users.query.graphql';
import DecisionLogDeciderSelect from 'ee/work_items/components/decision_log/decision_log_decider_select.vue';

Vue.use(VueApollo);

const autocompleteUser = ({ id, name, username }) => ({
  __typename: 'AutocompletedUser',
  id,
  name,
  username,
  avatarUrl: `/avatar/${username}`,
  webUrl: `/${username}`,
  webPath: `/${username}`,
  compositeIdentityEnforced: false,
  status: { __typename: 'UserStatus', availability: 'NOT_SET' },
  duoStatus: {
    __typename: 'DuoStatus',
    disabled: false,
    disabledReason: null,
    flowTriggerEvents: [],
  },
});

const participants = [
  autocompleteUser({ id: 'gid://gitlab/User/1', name: 'Avery Patel', username: 'avery' }),
  autocompleteUser({ id: 'gid://gitlab/User/2', name: 'Jordan Lee', username: 'jordan' }),
];

const outsider = autocompleteUser({
  id: 'gid://gitlab/User/9',
  name: 'Robin Diaz',
  username: 'robin',
});

const searchResponse = (users, isGroup) => ({
  data: isGroup
    ? {
        groupNamespace: { __typename: 'Group', id: 'gid://gitlab/Group/1', users },
        namespace: null,
      }
    : {
        namespace: { __typename: 'Project', id: 'gid://gitlab/Project/1', users },
      },
});

describe('DecisionLogDeciderSelect', () => {
  let wrapper;
  let searchHandler;

  const createComponent = ({
    value = '',
    users = [outsider],
    isGroup = false,
    selectedUser = null,
    searchFails = false,
  } = {}) => {
    searchHandler = searchFails
      ? jest.fn().mockRejectedValue(new Error('Network error'))
      : jest.fn().mockResolvedValue(searchResponse(users, isGroup));

    wrapper = mountExtended(DecisionLogDeciderSelect, {
      apolloProvider: createMockApollo([[usersSearchQuery, searchHandler]]),
      propsData: {
        value,
        participants,
        selectedUser,
        fullPath: 'group/project',
        isGroup,
      },
    });
  };

  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const listedNames = () =>
    findListbox()
      .props('items')
      .map((item) => item.text);
  const openDropdown = async () => {
    findListbox().vm.$emit('shown');
    await nextTick();
    await waitForPromises();
    await nextTick();
  };
  const searchUser = async (term) => {
    await openDropdown();
    findListbox().vm.$emit('search', term);
    jest.runOnlyPendingTimers();
    await waitForPromises();
  };

  beforeEach(() => {
    jest.useFakeTimers();
  });

  describe('before the dropdown opens', () => {
    beforeEach(() => {
      createComponent();
    });

    it('offers the participants', () => {
      expect(listedNames()).toEqual(['Avery Patel', 'Jordan Lee']);
    });

    it('asks the user to pick someone', () => {
      expect(findListbox().props('toggleText')).toBe('Select a user');
    });

    it('does not search', () => {
      expect(searchHandler).not.toHaveBeenCalled();
    });
  });

  describe('when the dropdown opens', () => {
    beforeEach(async () => {
      createComponent();
      await openDropdown();
    });

    it('searches the workspace for the wider list', () => {
      expect(searchHandler).toHaveBeenCalledWith(
        expect.objectContaining({ search: '', fullPath: 'group/project', isProject: true }),
      );
    });

    it('offers the participants and everyone the search found', () => {
      expect(listedNames()).toEqual(['Avery Patel', 'Jordan Lee', 'Robin Diaz']);
    });
  });

  describe('when the work item lives in a group', () => {
    beforeEach(async () => {
      createComponent({ isGroup: true });
      await openDropdown();
    });

    it('searches the group rather than a project', () => {
      expect(searchHandler).toHaveBeenCalledWith(expect.objectContaining({ isProject: false }));
    });
  });

  describe('when the user searches', () => {
    beforeEach(async () => {
      createComponent();
      await searchUser('robin');
    });

    it('passes the term to the query', () => {
      expect(searchHandler).toHaveBeenLastCalledWith(expect.objectContaining({ search: 'robin' }));
    });
  });

  describe('when the search term matches a participant by name', () => {
    beforeEach(async () => {
      createComponent({ users: [] });
      await searchUser('jord');
    });

    it('narrows the list to that participant without waiting for the server', () => {
      expect(listedNames()).toEqual(['Jordan Lee']);
    });
  });

  describe('when the search term matches a participant by username', () => {
    beforeEach(async () => {
      createComponent({ users: [] });
      await searchUser('avery');
    });

    it('narrows the list to that participant', () => {
      expect(listedNames()).toEqual(['Avery Patel']);
    });
  });

  describe('when the search fails', () => {
    beforeEach(async () => {
      jest.spyOn(Sentry, 'captureException').mockImplementation();
      createComponent({ searchFails: true });
      await searchUser('robin');
    });

    it('tells the user the list could not load', () => {
      expect(findListbox().props('noResultsText')).toBe(
        'Could not load users. Refresh the page and try again.',
      );
    });

    it('reports the failure', () => {
      expect(Sentry.captureException).toHaveBeenCalled();
    });
  });

  describe('when the user picks someone', () => {
    beforeEach(async () => {
      createComponent();
      await openDropdown();
      findListbox().vm.$emit('select', outsider.id);
      await nextTick();
    });

    it('reports the chosen user', () => {
      expect(wrapper.emitted('input')).toEqual([[outsider.id]]);
    });

    it('reports the whole user, which only this list can resolve', () => {
      expect(wrapper.emitted('select-user')).toEqual([[outsider]]);
    });
  });

  describe('when it opens on a decision decided by someone outside the participants', () => {
    beforeEach(() => {
      createComponent({ value: outsider.id, selectedUser: outsider });
    });

    it('names them, rather than showing a bare id', () => {
      expect(findListbox().props('toggleText')).toBe('Robin Diaz');
    });

    it('keeps them in the list', () => {
      expect(listedNames()).toContain('Robin Diaz');
    });
  });

  describe('when a search excludes the selected user', () => {
    beforeEach(async () => {
      createComponent({ value: participants[1].id, users: [] });
      await searchUser('avery');
    });

    it('still names them on the toggle', () => {
      expect(findListbox().props('toggleText')).toBe('Jordan Lee');
    });
  });
});
