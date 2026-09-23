import { useLocalStorageSpy, useWithoutLocalStorage } from 'helpers/local_storage_helper';
import {
  isWebSearchAvailable,
  loadWebSearchPreference,
  saveWebSearchPreference,
} from 'ee/ai/duo_agentic_chat/utils/web_search_preference';
import { WEB_SEARCH_PREFERENCE_STORAGE_KEY } from 'ee/ai/duo_agentic_chat/constants';

describe('web_search_preference', () => {
  describe('with localStorage available', () => {
    useLocalStorageSpy();

    describe('saveWebSearchPreference', () => {
      it.each([true, false])('stores %s under the preference key', (webSearchEnabled) => {
        saveWebSearchPreference(webSearchEnabled);

        expect(localStorage.setItem).toHaveBeenCalledWith(
          WEB_SEARCH_PREFERENCE_STORAGE_KEY,
          JSON.stringify(webSearchEnabled),
        );
      });
    });

    describe('loadWebSearchPreference', () => {
      it('round-trips a saved preference', () => {
        saveWebSearchPreference(true);

        expect(loadWebSearchPreference()).toBe(true);
      });

      it.each`
        scenario                | stored
        ${'stored false'}       | ${'false'}
        ${'nothing stored'}     | ${null}
        ${'malformed JSON'}     | ${'{'}
        ${'a non-boolean true'} | ${'"true"'}
      `('returns false for $scenario', ({ stored }) => {
        if (stored !== null) {
          localStorage.setItem(WEB_SEARCH_PREFERENCE_STORAGE_KEY, stored);
        }

        expect(loadWebSearchPreference()).toBe(false);
      });
    });
  });

  // Reading or writing site data throws outright in some private browsing modes,
  // which must not take the chat panel down with it.
  describe('with localStorage unavailable', () => {
    useWithoutLocalStorage();

    it('reports the preference as off rather than throwing', () => {
      expect(loadWebSearchPreference()).toBe(false);
    });

    it('swallows the write', () => {
      expect(() => saveWebSearchPreference(true)).not.toThrow();
    });
  });

  describe('isWebSearchAvailable', () => {
    it.each`
      dapWebSearch | webSearchAllowedForGroup | expected
      ${true}      | ${true}                  | ${true}
      ${true}      | ${false}                 | ${false}
      ${false}     | ${true}                  | ${false}
      ${false}     | ${false}                 | ${false}
    `(
      'is $expected when the flag is $dapWebSearch and the group grant is $webSearchAllowedForGroup',
      ({ dapWebSearch, webSearchAllowedForGroup, expected }) => {
        expect(isWebSearchAvailable({ dapWebSearch }, webSearchAllowedForGroup)).toBe(expected);
      },
    );

    it('is false when no feature flags are provided at all', () => {
      expect(isWebSearchAvailable(undefined, true)).toBe(false);
    });
  });
});
