import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlTokenSelector } from '@gitlab/ui';
import UserOverrideSelect from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/user_override_select.vue';
import searchAllUsersQuery from '~/graphql_shared/queries/users_search_all.query.graphql';
import searchGroupUsersQuery from '~/graphql_shared/queries/group_users_search.query.graphql';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import {
  mockSearchAllUsersResult,
  mockSearchGroupUsersResult,
  mockSearchUsers,
} from 'ee_jest/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/mock_data';

jest.mock('~/lib/logger');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('CreditCapsUserOverrideSelect', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;
  /** @type {jest.Mock} */
  let searchAllUsersHandler;
  /** @type {jest.Mock} */
  let searchGroupUsersHandler;

  const createComponent = ({ provide = {}, props = {} } = {}) => {
    const apolloProvider = createMockApollo([
      [searchAllUsersQuery, searchAllUsersHandler],
      [searchGroupUsersQuery, searchGroupUsersHandler],
    ]);

    wrapper = shallowMountExtended(UserOverrideSelect, {
      apolloProvider,
      propsData: { value: [], ...props },
      provide: { namespacePath: null, ...provide },
    });
  };

  const findTokenSelector = () => wrapper.findComponent(GlTokenSelector);
  const findErrorAlert = () => wrapper.findByTestId('user-override-select-error-alert');

  beforeEach(() => {
    searchAllUsersHandler = jest.fn().mockResolvedValue(mockSearchAllUsersResult);
    searchGroupUsersHandler = jest.fn().mockResolvedValue(mockSearchGroupUsersResult);
  });

  describe('rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the token selector', () => {
      expect(findTokenSelector().exists()).toBe(true);
    });

    it('passes disabled=false by default', () => {
      expect(findTokenSelector().attributes('disabled')).toBeUndefined();
    });

    it('passes disabled prop to the token selector', () => {
      createComponent({ props: { value: [], disabled: true } });
      expect(findTokenSelector().attributes('disabled')).toBeDefined();
    });

    it('does not show an error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('placeholder text', () => {
    it('shows placeholder when no users selected', () => {
      createComponent({ props: { value: [] } });
      expect(findTokenSelector().props('placeholder')).toBe('Search for a user');
    });

    it('hides placeholder when users are selected', () => {
      createComponent({ props: { value: [mockSearchUsers[0]] } });
      expect(findTokenSelector().props('placeholder')).toBe('');
    });
  });

  describe('user search', () => {
    const search = async (term) => {
      findTokenSelector().vm.$emit('text-input', term);
      await nextTick();
      jest.runAllTimers();
      await waitForPromises();
    };

    beforeEach(() => {
      jest.useFakeTimers();
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    describe('on SM (namespacePath=null)', () => {
      it('uses searchAllUsers query', async () => {
        createComponent({ provide: { namespacePath: null } });
        await search('diana');
        expect(searchAllUsersHandler).toHaveBeenLastCalledWith(
          expect.objectContaining({ search: 'diana' }),
        );
      });

      it('does not call searchGroupUsers', async () => {
        createComponent({ provide: { namespacePath: null } });
        await search('diana');
        expect(searchGroupUsersHandler).not.toHaveBeenCalled();
      });
    });

    describe('on SaaS (namespacePath set)', () => {
      it('uses searchGroupUsers query with fullPath', async () => {
        createComponent({ provide: { namespacePath: 'my-group' } });
        await search('diana');
        expect(searchGroupUsersHandler).toHaveBeenLastCalledWith(
          expect.objectContaining({ search: 'diana', fullPath: 'my-group' }),
        );
      });

      it('does not call searchAllUsers', async () => {
        createComponent({ provide: { namespacePath: 'my-group' } });
        await search('diana');
        expect(searchAllUsersHandler).not.toHaveBeenCalled();
      });
    });

    it('skips query when fewer than 3 characters typed', async () => {
      createComponent();
      findTokenSelector().vm.$emit('text-input', 'di');
      jest.runAllTimers();
      await waitForPromises();
      expect(searchAllUsersHandler).not.toHaveBeenCalledWith(
        expect.objectContaining({ search: 'di' }),
      );
    });

    it('does not skip the query when the search term is cleared', async () => {
      createComponent();
      await search('diana');
      await search('');
      expect(searchAllUsersHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ search: '' }),
      );
    });
  });

  describe('when the search query fails', () => {
    const search = async (term) => {
      findTokenSelector().vm.$emit('text-input', term);
      await nextTick();
      jest.runAllTimers();
      await waitForPromises();
    };

    beforeEach(async () => {
      jest.useFakeTimers();
      createComponent();
      await waitForPromises();
      await search('diana');
      searchAllUsersHandler.mockRejectedValue(new Error('Network error'));
      await search('clark');
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    it('shows an error alert', () => {
      expect(findErrorAlert().exists()).toBe(true);
      expect(findErrorAlert().text()).toBe('Something went wrong while searching for users.');
    });

    it('clears stale search results', () => {
      expect(findTokenSelector().props('dropdownItems')).toEqual([]);
    });

    it('logs the error', () => {
      expect(logError).toHaveBeenCalledWith(expect.any(Error));
    });

    it('captures the error in Sentry', () => {
      expect(captureException).toHaveBeenCalledWith(expect.any(Error));
    });

    describe('when a new search is triggered', () => {
      it('hides the alert', async () => {
        searchAllUsersHandler.mockResolvedValue(mockSearchAllUsersResult);
        await search('bob');
        expect(findErrorAlert().exists()).toBe(false);
      });
    });
  });

  describe('no results message', () => {
    it('shows too-short message when fewer than 3 characters typed', async () => {
      createComponent();
      findTokenSelector().vm.$emit('text-input', 'di');
      await nextTick();
      expect(findTokenSelector().props('placeholder')).not.toBeNull();
      expect(wrapper.text()).toContain('Type at least 3 characters to search for users.');
    });

    it('shows no users found message otherwise', () => {
      createComponent();
      expect(wrapper.text()).toContain('No users found.');
    });
  });

  describe('emitting input', () => {
    it('emits input when token selector emits input', async () => {
      createComponent();
      findTokenSelector().vm.$emit('input', [mockSearchUsers[0]]);
      await nextTick();
      expect(wrapper.emitted('input')).toEqual([[[mockSearchUsers[0]]]]);
    });
  });
});
