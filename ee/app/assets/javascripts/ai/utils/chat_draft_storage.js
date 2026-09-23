/**
 * Persists an unsent Duo Chat draft, keyed per user and thread, so it survives a page
 * reload. Storage goes through `~/lib/utils/autosave`, the same primitive the note and
 * comment forms use, so a browser that refuses localStorage costs the draft rather than
 * throwing out of a lifecycle hook or the unload listener.
 */
import { debounce } from 'lodash-es';
import { clearDraft, getDraft, updateDraft } from '~/lib/utils/autosave';

const DRAFT_STORAGE_KEY_PREFIX = 'duo_chat_draft';
const NEW_THREAD_KEY = 'new';

const DRAFT_SAVE_DEBOUNCE_MS = 300;

// Callers pass whichever id shape their component was handed: the panel supplies the
// current user as a global id, thread ids arrive already reduced. Keep only the trailing
// segment so both shapes name the same key.
const localId = (id) => (id ? `${id}`.split('/').pop() : id);

/**
 * Builds the autosave key for a draft, scoped by user, thread, and chat variant.
 * Threads that don't exist yet fall back to the literal 'new', a bucket both chat modes
 * share so a draft survives the agentic/classic toggle.
 * A missing `userId` yields no key at all: an unscoped key would hand one user's draft to
 * the next on a shared browser, so dropping the draft is the safer failure.
 * @param {Object} options - Key components
 * @param {string} options.userId - Current user's ID or global ID; without it there is no key
 * @param {string} [options.threadId] - Current thread ID; falsy before a thread exists
 * @param {string} [options.variant] - Chat variant marker, e.g. 'classic'; agentic chat omits
 *   it, and it is ignored for the shared 'new' bucket
 * @returns {?string} The storage key, with falsy optional parts dropped, or null
 */
export const buildDraftStorageKey = ({ userId, threadId, variant } = {}) => {
  if (!userId) return null;

  const thread = localId(threadId);

  // The variant scopes real threads only, where an agentic workflow id and a classic
  // conversation id both reduce to a bare number and would otherwise collide.
  return [DRAFT_STORAGE_KEY_PREFIX, localId(userId), thread && variant, thread || NEW_THREAD_KEY]
    .filter(Boolean)
    .join('_');
};

/**
 * Removes a stored draft. For callers deleting the conversation a draft belonged to,
 * which have no live store and no composer to keep in step.
 * @param {Object} keyParts - Same shape `buildDraftStorageKey` takes
 */
export const removeDraft = (keyParts) => {
  const key = buildDraftStorageKey(keyParts);

  if (key) clearDraft(key);
};

/**
 * Creates a draft store for a key that can change while typing, e.g. when switching threads.
 * @param {Function} getKey - Returns the current storage key, or a falsy value to persist
 *   nothing; called on every read, save, and clear
 * @returns {Object} read() returns the stored draft or ''; save(draft) is debounced and clears
 *   the key when draft is empty; clear() removes the key the draft was last read or saved
 *   under, immediately; destroy() lands any waiting draft and detaches the unload listener
 */
export const createDraftStorage = (getKey) => {
  const write = (key, draft) => {
    if (draft) {
      updateDraft(key, draft);
    } else {
      clearDraft(key);
    }
  };

  // The waiting draft is held here rather than in the debounced call's arguments, because
  // lodash keeps only the arguments of the last call: saving under a new key would drop a
  // draft still waiting to be written under the old one.
  let pending = null;

  // The key the store last worked with. `clear()` runs straight after an event that can
  // move the conversation, so resolving the key again there would remove the key the
  // caller has just arrived at and leave behind the draft it meant to clear.
  let boundKey = null;

  const flush = () => {
    if (!pending) return;

    const { key, draft } = pending;
    pending = null;
    write(key, draft);
  };

  const flushLater = debounce(flush, DRAFT_SAVE_DEBOUNCE_MS);

  // A reload landing inside the debounce window is exactly what this feature exists to
  // survive, so the waiting draft has to beat the page going away. `pagehide` rather than
  // `beforeunload`: it also fires when the page enters the back/forward cache.
  const flushNow = () => {
    flushLater.cancel();
    flush();
  };

  window.addEventListener('pagehide', flushNow);

  const read = () => {
    const key = getKey();
    boundKey = key;
    if (!key) return '';

    // A waiting write is the newest value for its key: the debounce means storage
    // still holds the previous one, or nothing at all for a draft never yet saved.
    if (pending && pending.key === key) return pending.draft;

    const value = getDraft(key);
    return typeof value === 'string' ? value : '';
  };

  const save = (draft) => {
    const key = getKey();
    boundKey = key;
    if (!key) return;

    // The key changed while a draft was waiting, so the user has moved to another
    // thread. Land that draft under the thread it was typed in before this one takes
    // over the timer.
    if (pending && pending.key !== key) flush();

    pending = { key, draft };
    flushLater();
  };

  return {
    read,
    save,
    // Moves a draft between keys, for a conversation that has just been assigned an id.
    // Both keys are explicit because callers differ on when they run: one is a key-change
    // watcher, the other runs just before the navigation that changes the key. Takes the
    // text from the caller so a write still waiting out the debounce moves too, and lands
    // it immediately, since a deliberate move has nothing to wait for.
    carryOver(fromKey, toKey, text) {
      if (pending && pending.key === fromKey) {
        flushLater.cancel();
        pending = null;
      }

      if (fromKey) clearDraft(fromKey);
      if (toKey) write(toKey, text);
      boundKey = toKey;
    },
    clear() {
      const key = boundKey ?? getKey();

      // Land any pending write to another key first, matching `save`, so text
      // typed into another thread isn't lost.
      if (pending && pending.key !== key) flush();

      flushLater.cancel();
      pending = null;

      if (key) clearDraft(key);
    },
    destroy() {
      window.removeEventListener('pagehide', flushNow);
      flushNow();
    },
  };
};
