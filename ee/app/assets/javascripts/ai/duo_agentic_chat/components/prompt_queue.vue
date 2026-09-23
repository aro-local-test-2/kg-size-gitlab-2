<script>
import { v4 as uuidv4 } from 'uuid';
import {
  getSessionStorageValue,
  saveSessionStorageValue,
  removeSessionStorageValue,
} from '~/lib/utils/local_storage';
import { normalizeRender } from '~/lib/utils/vue3compat/normalize_render';
import { DUO_CHAT_QUEUED_PROMPTS_STORAGE_KEY } from 'ee/ai/constants';

const isReload = () => window.performance?.getEntriesByType?.('navigation')?.[0]?.type === 'reload';

// Only the first queue of a page load discards a stale one, so re-opening the
// chat later in that same page keeps whatever the user has queued since.
let staleQueueDiscarded = false;

/**
 * A link navigation carries the queue over to the next page, but a reload is the
 * user deliberately resetting the chat, and prompts they queued before it should
 * not fire on their own afterwards. A queue also belongs to the thread it was
 * typed in: picking another thread from the history list mounts this component
 * afresh against a different workflow, and those prompts were never meant for it.
 */
const loadQueuedPrompts = (workflowId) => {
  const discard = !staleQueueDiscarded && isReload();
  staleQueueDiscarded = true;

  if (discard) {
    removeSessionStorageValue(DUO_CHAT_QUEUED_PROMPTS_STORAGE_KEY);
    return [];
  }

  const { value } = getSessionStorageValue(DUO_CHAT_QUEUED_PROMPTS_STORAGE_KEY);
  if (!value) return [];

  // The storage key is versioned, so anything read here was written by a bundle that
  // agrees on the shape. The guard is for a hand-edited or truncated value.
  const prompts = Array.isArray(value.prompts) ? value.prompts.filter((item) => item?.prompt) : [];

  // A record that exists but is not ours: drop it rather than leave it to be read
  // again by the next mount.
  if (!prompts.length || value.workflowId !== workflowId) {
    removeSessionStorageValue(DUO_CHAT_QUEUED_PROMPTS_STORAGE_KEY);
    return [];
  }

  return prompts;
};

/**
 * Renderless owner of the prompts a user submits while an agent turn is in
 * progress. Holds them in sessionStorage so a queue survives a page navigation
 * the same way the active workflow does, and releases them one at a time
 * through `send` whenever `canSend` says the chat could take a prompt.
 */
export default normalizeRender({
  name: 'PromptQueue',
  props: {
    /**
     * Whether a queued prompt may go out on its own right now. The queue drains the
     * moment this turns true, so it covers both every reason a prompt would be
     * dropped and the states only the user should act in.
     */
    canSend: {
      type: Boolean,
      required: true,
    },
    /**
     * The workflow these prompts were typed against, so a later mount can tell
     * whether they still belong to the thread it shows. Null until the first turn.
     */
    workflowId: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['change', 'send'],
  data() {
    return {
      prompts: loadQueuedPrompts(this.workflowId),
    };
  },
  watch: {
    prompts(prompts) {
      this.persist();
      this.$emit('change', prompts);
    },
    // A prompt queued before createWorkflow answers lands with no owner, so re-stamp
    // it once the id arrives. Abandoning a thread in place is the caller's to handle;
    // only it knows a base command is meant to carry the queue over.
    workflowId: 'persist',
    canSend: 'drain',
  },
  created() {
    if (this.prompts.length) {
      this.$emit('change', this.prompts);
    }
  },
  methods: {
    // enqueue, remove and clear are the imperative surface the state manager
    // drives through its ref.
    enqueue(prompt) {
      this.prompts = [...this.prompts, { id: uuidv4(), prompt }];
    },
    remove(id) {
      this.prompts = this.prompts.filter((prompt) => prompt.id !== id);
    },
    clear() {
      this.prompts = [];
    },
    persist() {
      if (this.prompts.length) {
        saveSessionStorageValue(DUO_CHAT_QUEUED_PROMPTS_STORAGE_KEY, {
          workflowId: this.workflowId,
          prompts: this.prompts,
        });
      } else {
        removeSessionStorageValue(DUO_CHAT_QUEUED_PROMPTS_STORAGE_KEY);
      }
    },
    async drain() {
      if (!this.canSend || !this.prompts.length) return;

      const [next] = this.prompts;
      this.remove(next.id);
      this.$emit('send', next.prompt);

      // Base commands (/reset, /clear, /new) and easter eggs are handled without
      // starting a turn, so canSend never flips and this watcher won't run again.
      // Re-check once the parent has re-rendered so later prompts don't stall.
      await this.$nextTick();
      this.drain();
    },
  },
  render: () => null,
});
</script>
