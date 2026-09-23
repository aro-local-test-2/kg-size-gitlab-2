import { useLocalStorageSpy } from 'helpers/local_storage_helper';
import { buildDraftStorageKey, createDraftStorage } from 'ee/ai/utils/chat_draft_storage';

describe('chat_draft_storage', () => {
  useLocalStorageSpy();

  describe('buildDraftStorageKey', () => {
    it.each`
      parts                                                       | expected
      ${{ userId: 'user-42', threadId: '99' }}                    | ${'duo_chat_draft_user-42_99'}
      ${{ userId: 'user-42', threadId: '7', variant: 'classic' }} | ${'duo_chat_draft_user-42_classic_7'}
      ${{ userId: 'user-42' }}                                    | ${'duo_chat_draft_user-42_new'}
    `('builds $expected from $parts', ({ parts, expected }) => {
      expect(buildDraftStorageKey(parts)).toBe(expected);
    });

    // Both chat modes compose into the same bucket before a thread exists, so a draft
    // survives the agentic/classic toggle. Real threads stay separated, because an
    // agentic workflow id and a classic conversation id both reduce to a bare number.
    it('ignores the variant for the shared new-thread bucket', () => {
      expect(buildDraftStorageKey({ userId: 'user-42', variant: 'classic' })).toBe(
        buildDraftStorageKey({ userId: 'user-42' }),
      );
    });

    it('keeps the variant apart once a thread exists', () => {
      expect(
        buildDraftStorageKey({ userId: 'user-42', threadId: '7', variant: 'classic' }),
      ).not.toBe(buildDraftStorageKey({ userId: 'user-42', threadId: '7' }));
    });

    // The panel hands the current user down as a global id, so the key would otherwise
    // carry the whole `gid://gitlab/User/1` path.
    it.each`
      parts                                                                        | expected
      ${{ userId: 'gid://gitlab/User/1', threadId: '99' }}                         | ${'duo_chat_draft_1_99'}
      ${{ userId: 'gid://gitlab/User/1', threadId: 'gid://gitlab/DuoWorkflow/9' }} | ${'duo_chat_draft_1_9'}
      ${{ userId: 'gid://gitlab/User/1' }}                                         | ${'duo_chat_draft_1_new'}
    `('reduces global ids, building $expected', ({ parts, expected }) => {
      expect(buildDraftStorageKey(parts)).toBe(expected);
    });

    // An unscoped key would hand one user's draft to whoever logs in next on the same
    // browser, so there is deliberately no key to fall back to.
    it.each`
      parts                 | desc
      ${{ threadId: '99' }} | ${'a thread but no user'}
      ${{}}                 | ${'nothing'}
    `('builds no key from $desc', ({ parts }) => {
      expect(buildDraftStorageKey(parts)).toBe(null);
    });
  });

  describe('createDraftStorage', () => {
    const key = 'duo_chat_draft_user-42_99';
    const otherKey = 'duo_chat_draft_user-42_100';
    // `autosave` namespaces everything it stores, so the draft key and the localStorage
    // key it lands under are not the same string.
    const stored = (draftKey) => `autosave/${draftKey}`;
    let currentKey;
    let storage;

    beforeAll(() => {
      global.JEST_DEBOUNCE_THROTTLE_TIMEOUT = 300;
    });

    afterAll(() => {
      global.JEST_DEBOUNCE_THROTTLE_TIMEOUT = undefined;
    });

    beforeEach(() => {
      currentKey = key;
      storage = createDraftStorage(() => currentKey);
    });

    afterEach(() => {
      storage.destroy();
    });

    describe('read', () => {
      it('returns the stored draft', () => {
        localStorage.setItem(stored(key), 'unsent message');

        expect(storage.read()).toBe('unsent message');
      });

      it('returns an empty string when nothing is stored', () => {
        expect(storage.read()).toBe('');
      });
    });

    describe('save', () => {
      it('defers the write until typing settles', () => {
        storage.save('unsent message');

        expect(localStorage.setItem).not.toHaveBeenCalled();

        jest.runAllTimers();

        expect(localStorage.setItem).toHaveBeenCalledWith(stored(key), 'unsent message');
      });

      it('removes the key instead of storing an empty draft', () => {
        localStorage.setItem(stored(key), 'unsent message');

        storage.save('');
        jest.runAllTimers();

        expect(localStorage.removeItem).toHaveBeenCalledWith(stored(key));
      });

      it('writes to the key that was current when save was called', () => {
        storage.save('typed in the first thread');
        currentKey = otherKey;
        jest.runAllTimers();

        expect(localStorage.setItem).toHaveBeenCalledWith(stored(key), 'typed in the first thread');
      });

      // Switching threads mid-debounce is the whole reason the waiting draft is held
      // outside the debounced call: lodash would keep only the second key's arguments.
      it('lands a waiting draft before saving under a new key', () => {
        storage.save('typed in the first thread');
        currentKey = otherKey;
        storage.save('typed in the second thread');

        expect(localStorage.setItem).toHaveBeenCalledWith(stored(key), 'typed in the first thread');

        jest.runAllTimers();

        expect(localStorage.setItem).toHaveBeenCalledWith(
          stored(otherKey),
          'typed in the second thread',
        );
      });
    });

    describe('when there is no key to scope the draft to', () => {
      beforeEach(() => {
        currentKey = null;
      });

      it('reads nothing', () => {
        expect(storage.read()).toBe('');
      });

      it('persists nothing', () => {
        storage.save('unsent message');
        jest.runAllTimers();

        expect(localStorage.setItem).not.toHaveBeenCalled();
      });

      it('removes nothing on clear', () => {
        storage.clear();

        expect(localStorage.removeItem).not.toHaveBeenCalled();
      });
    });

    // Safari private browsing and Chrome with site data blocked both throw here, and
    // reads run from a mounted hook while writes run from a timer and the unload
    // listener, so throwing costs more than the draft does.
    describe('when the browser refuses storage', () => {
      const refuse = () => {
        throw new DOMException('denied', 'SecurityError');
      };

      beforeEach(() => {
        jest.spyOn(console, 'error').mockImplementation(() => {});
        localStorage.getItem.mockImplementation(refuse);
        localStorage.setItem.mockImplementation(refuse);
        localStorage.removeItem.mockImplementation(refuse);
      });

      it('degrades to no draft rather than throwing', () => {
        expect(storage.read()).toBe('');

        storage.save('unsent message');

        expect(() => jest.runAllTimers()).not.toThrow();
        expect(() => storage.clear()).not.toThrow();
      });
    });

    describe('read with a waiting write', () => {
      // Regression: hopping to another key and back inside the debounce window used to
      // read nothing, so the caller restored an empty value over the waiting draft.
      it('returns the waiting draft rather than what storage still holds', () => {
        localStorage.setItem(stored(key), 'older saved value');

        storage.save('typed but not yet written');

        expect(storage.read()).toBe('typed but not yet written');
      });

      it('returns the waiting draft when storage holds nothing at all', () => {
        storage.save('typed but not yet written');

        expect(storage.read()).toBe('typed but not yet written');
      });

      it('ignores a waiting draft belonging to another key', () => {
        storage.save('typed in the first thread');
        currentKey = otherKey;

        expect(storage.read()).toBe('');
      });
    });

    describe('carryOver', () => {
      const toKey = otherKey;

      it('writes the text to the destination immediately', () => {
        storage.carryOver(key, toKey, 'follow-up text');

        expect(localStorage.getItem(stored(toKey))).toBe('follow-up text');
      });

      it('drops the key it came from', () => {
        localStorage.setItem(stored(key), 'follow-up text');

        storage.carryOver(key, toKey, 'follow-up text');

        expect(localStorage.getItem(stored(key))).toBe(null);
      });

      it('carries a write still waiting out the debounce', () => {
        storage.save('typed but not yet written');

        storage.carryOver(key, toKey, 'typed but not yet written');
        jest.runAllTimers();

        expect(localStorage.getItem(stored(toKey))).toBe('typed but not yet written');
        expect(localStorage.getItem(stored(key))).toBe(null);
      });

      it('removes the destination instead of storing an empty draft', () => {
        localStorage.setItem(stored(toKey), 'stale');

        storage.carryOver(key, toKey, '');

        expect(localStorage.getItem(stored(toKey))).toBe(null);
      });
    });

    describe('clear', () => {
      it('removes the key immediately', () => {
        localStorage.setItem(stored(key), 'unsent message');

        storage.clear();

        expect(localStorage.removeItem).toHaveBeenCalledWith(stored(key));
        expect(storage.read()).toBe('');
      });

      it('drops a pending write so it cannot restore the draft', () => {
        storage.save('unsent message');
        storage.clear();
        jest.runAllTimers();

        expect(localStorage.setItem).not.toHaveBeenCalled();
        expect(storage.read()).toBe('');
      });

      // Callers clear straight after emitting a send, and that emit can move the
      // conversation, so the current key is no longer the one the draft is under.
      it('removes the key the draft was saved under, not the key that is current now', () => {
        storage.save('typed in the first thread');
        currentKey = otherKey;

        storage.clear();

        expect(localStorage.removeItem).toHaveBeenCalledWith(stored(key));
        expect(localStorage.removeItem).not.toHaveBeenCalledWith(stored(otherKey));
      });

      it('lands a waiting draft belonging to another key', () => {
        storage.save('typed in the first thread');
        currentKey = otherKey;
        storage.read();

        storage.clear();
        jest.runAllTimers();

        expect(localStorage.setItem).toHaveBeenCalledWith(stored(key), 'typed in the first thread');
        expect(localStorage.removeItem).toHaveBeenCalledWith(stored(otherKey));
      });

      it('removes the destination once a draft has been carried over', () => {
        storage.carryOver(key, otherKey, 'carried across');

        storage.clear();

        expect(localStorage.removeItem).toHaveBeenCalledWith(stored(otherKey));
      });
    });

    // The reload this feature exists to survive can land inside the debounce window.
    describe('when the page goes away', () => {
      it('lands a waiting draft', () => {
        storage.save('unsent message');

        window.dispatchEvent(new Event('pagehide'));

        expect(localStorage.setItem).toHaveBeenCalledWith(stored(key), 'unsent message');
      });
    });

    describe('destroy', () => {
      it('lands a waiting draft', () => {
        storage.save('unsent message');

        storage.destroy();

        expect(localStorage.setItem).toHaveBeenCalledWith(stored(key), 'unsent message');
      });

      it('stops listening for unload', () => {
        storage.destroy();
        storage.save('unsent message');

        window.dispatchEvent(new Event('pagehide'));

        expect(localStorage.setItem).not.toHaveBeenCalled();
      });
    });
  });
});
