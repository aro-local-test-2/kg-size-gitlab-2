import { nextTick } from 'vue';

import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import BoardFilteredSearch from 'ee/boards/components/board_filtered_search.vue';
import BoardFilteredSearchCe from '~/boards/components/board_filtered_search.vue';
import * as urlUtility from '~/lib/utils/url_utility';

describe('ee/BoardFilteredSearch', () => {
  let wrapper;
  let store;
  const updateTokensSpy = jest.fn();

  const createComponent = ({ provide = {} } = {}) => {
    wrapper = mountExtended(BoardFilteredSearch, {
      store,
      propsData: {
        tokens: [],
        board: {},
        filters: {},
      },
      provide: {
        boardBaseUrl: 'root',
        initialFilterParams: [],
        ...provide,
      },
      stubs: {
        BoardFilteredSearchCe: stubComponent(BoardFilteredSearchCe, {
          methods: { updateTokens: updateTokensSpy },
        }),
      },
    });
  };

  const findFilteredSearch = () => wrapper.findComponent(BoardFilteredSearchCe);

  beforeEach(() => {
    createComponent();
    jest.spyOn(urlUtility, 'updateHistory');
  });

  describe('when the initial board loads with a scope not yet in the URL', () => {
    beforeEach(async () => {
      wrapper.setProps({
        board: { id: 'gid://gitlab/Board/1', labels: [{ title: 'test', color: 'black', id: '1' }] },
      });
      await nextTick();
    });

    it('updates the url and filter params', () => {
      expect(urlUtility.updateHistory).toHaveBeenCalledWith({
        url: '?label_name[]=test',
      });

      expect(findFilteredSearch().props()).toEqual(
        expect.objectContaining({ eeFilters: { labelName: ['test'] } }),
      );
    });

    it('rebuilds the tokens', () => {
      expect(updateTokensSpy).toHaveBeenCalled();
    });
  });

  describe('when the initial board loads without a scope', () => {
    beforeEach(async () => {
      wrapper.setProps({ board: { id: 'gid://gitlab/Board/1', name: 'Dev', labels: [] } });
      await nextTick();
    });

    it('does not update the url', () => {
      expect(urlUtility.updateHistory).not.toHaveBeenCalled();
    });

    it('does not rebuild the tokens', () => {
      expect(updateTokensSpy).not.toHaveBeenCalled();
    });
  });

  describe('when switching to another board', () => {
    beforeEach(async () => {
      wrapper.setProps({ board: { id: 'gid://gitlab/Board/1', labels: [] } });
      await nextTick();
      updateTokensSpy.mockClear();
      urlUtility.updateHistory.mockClear();

      wrapper.setProps({ board: { id: 'gid://gitlab/Board/2', labels: [] } });
      await nextTick();
    });

    it('updates the url to the new board', () => {
      expect(urlUtility.updateHistory).toHaveBeenCalledWith({ url: 'root/2' });
    });

    it('rebuilds the tokens', () => {
      expect(updateTokensSpy).toHaveBeenCalled();
    });
  });
});
