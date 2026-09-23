import { shallowMount } from '@vue/test-utils';
import { GlFilteredSearch } from '@gitlab/ui';
import { markRaw, nextTick } from 'vue';
import DependenciesFilteredSearch from 'ee/dependencies/components/filtered_search/dependencies_filtered_search.vue';
import ComponentToken from 'ee/dependencies/components/filtered_search/tokens/component_token.vue';
import createStore from 'ee/dependencies/store';

describe('DependenciesFilteredSearch', () => {
  let wrapper;
  let store;

  const defaultToken = {
    title: 'Component',
    type: 'component_names',
    multiSelect: true,
    token: markRaw(ComponentToken),
  };

  const defaultPropsData = {
    filteredSearchId: 'some-filtered-search-id',
    tokens: [defaultToken],
  };

  const createVuexStore = () => {
    store = createStore();
    jest.spyOn(store, 'dispatch').mockImplementation();
  };

  const createComponent = ({ props = {}, slot = '', namespaceType = 'project' } = {}) => {
    wrapper = shallowMount(DependenciesFilteredSearch, {
      store,
      propsData: {
        ...defaultPropsData,
        ...props,
      },
      provide: {
        namespaceType,
      },
      scopedSlots: { default: slot },
    });
  };

  const findFilteredSearch = () => wrapper.findComponent(GlFilteredSearch);

  beforeEach(createVuexStore);

  describe('GlFilteredSearch', () => {
    beforeEach(createComponent);

    it('sets the basic props correctly', () => {
      expect(findFilteredSearch().props()).toMatchObject({
        termsAsTokens: true,
        value: [],
      });
    });

    it('sets the id attribute', () => {
      const { filteredSearchId } = defaultPropsData;
      expect(findFilteredSearch().attributes('id')).toBe(filteredSearchId);
    });

    it('displays the correct placeholder', () => {
      expect(findFilteredSearch().props('placeholder')).toBe('Search or filter dependencies…');
    });

    it('passes the token configuration', () => {
      expect(findFilteredSearch().props('availableTokens')).toMatchObject(
        expect.arrayContaining([
          expect.objectContaining({
            ...defaultToken,
          }),
        ]),
      );
    });

    // Temporary until https://gitlab.com/gitlab-org/gitlab/-/issues/612168
    describe('appliedTrackedRefs', () => {
      const malwareToken = {
        title: 'Malware',
        type: 'malware',
        multiSelect: false,
        token: markRaw({}),
      };
      const tokensWithMalware = [defaultToken, malwareToken];

      const mainRef = { id: 'gid://gitlab/Security::ProjectTrackedContext/1', name: 'main' };
      const featureRef = { id: 'gid://gitlab/Security::ProjectTrackedContext/2', name: 'feature' };

      const findTokenByType = (type) =>
        findFilteredSearch()
          .props('availableTokens')
          .find((token) => token.type === type);

      const getAppliedTrackedRefs = () => findTokenByType('malware').appliedTrackedRefs;

      const setTrackedRefFilter = (trackedRefIds) => {
        store.state.searchFilterParameters = trackedRefIds ? { trackedRefIds } : {};
      };

      const createWithMalware = () => createComponent({ props: { tokens: tokensWithMalware } });

      it.each([
        ['no ref filter is applied', undefined, []],
        ['a single ref is applied', [mainRef], [mainRef]],
        ['all tracked refs are applied', ['ALL'], ['ALL']],
        ['a ref is applied next to all tracked refs', ['ALL', featureRef], ['ALL', featureRef]],
      ])('passes the refs the malware token needs when %s', (name, applied, expected) => {
        setTrackedRefFilter(applied);
        createWithMalware();

        expect(getAppliedTrackedRefs()).toEqual(expected);
      });

      it('updates when the applied refs change', async () => {
        createWithMalware();
        setTrackedRefFilter([featureRef]);
        await nextTick();

        expect(getAppliedTrackedRefs()).toEqual([featureRef]);
      });

      it('is passed only to the malware token', () => {
        createWithMalware();

        expect(findTokenByType('component_names')).not.toHaveProperty('appliedTrackedRefs');
        expect(findTokenByType('component_names')).toMatchObject(defaultToken);
      });
    });

    it('passes the value prop', () => {
      const value = [{ type: 'trackedRefIds', value: { data: [{ id: '1', name: 'main' }] } }];
      createComponent({ props: { value } });

      expect(findFilteredSearch().props('value')).toEqual(value);
    });

    describe('submit', () => {
      it('dispatches the "fetchDependenciesViaGraphQL" Vuex action', () => {
        createComponent();
        expect(store.dispatch).not.toHaveBeenCalled();

        const filterPayload = [{ type: 'license', value: { data: ['MIT'] } }];
        findFilteredSearch().vm.$emit('submit', filterPayload);

        expect(store.dispatch).toHaveBeenCalledWith('fetchDependenciesViaGraphQL');
      });

      it('dispatches the "fetchDependencies" Vuex action when namespaceType is group', () => {
        createComponent({ namespaceType: 'group' });
        expect(store.dispatch).not.toHaveBeenCalled();

        const filterPayload = [{ type: 'license', value: { data: ['MIT'] } }];
        findFilteredSearch().vm.$emit('submit', filterPayload);

        expect(store.dispatch).toHaveBeenCalledWith('fetchDependencies', {
          page: 1,
        });
      });
    });
  });
});
