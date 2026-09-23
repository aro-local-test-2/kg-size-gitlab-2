<script>
import { GlButton, GlCollapse, GlIcon } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { clearDraft } from '~/lib/utils/autosave';
import { s__ } from '~/locale';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import createNoteMutation from '~/work_items/graphql/notes/create_work_item_note.mutation.graphql';
import toggleResolveDiscussionMutation from '~/work_items/graphql/notes/toggle_work_item_note_resolve_discussion.mutation.graphql';
import { ANSWER_ID_CUSTOM, PARSE_STATUS_OK, QUESTION_TYPE_CLOSED } from '../../constants';
import {
  buildDuoAnswer,
  buildDuoAnswers,
  parseDuoAnswer,
  parseDuoAnswerLabels,
  parseDuoQuestion,
  stripDuoAnswerMarker,
} from '../../utils/duo_question';
import DuoCustomAnswerInput from './duo_custom_answer_input.vue';
import DuoMultiSelectOptions from './duo_multi_select_options.vue';
import DuoSingleSelectOptions from './duo_single_select_options.vue';

/**
 * Renders the clarifying question a workplan flow attached to its comment, so a
 * choice can be made in the discussion instead of by typing prose back at the agent.
 *
 * Answering posts the choice as a reply and resolves the thread. Resolving is the
 * part that matters: `Discussions::ResolveService` publishes
 * `WorkItems::DiscussionResolvedEvent`, and once every question the run posted is
 * resolved, `ContinueWorkplanAfterDiscussionsResolvedWorker` resumes the paused
 * workflow with the replies.
 *
 * An answer can also be written out when no option fits. That reply carries
 * `ANSWER_ID_CUSTOM`, so a decision log can tell a typed answer from a picked one.
 */
export default {
  name: 'DuoQuestionNote',
  components: {
    GlButton,
    GlCollapse,
    GlIcon,
    DuoCustomAnswerInput,
    DuoMultiSelectOptions,
    DuoSingleSelectOptions,
  },
  mixins: [glFeatureFlagMixin()],
  props: {
    note: {
      type: Object,
      required: true,
    },
    workItemId: {
      type: String,
      required: true,
    },
    discussionId: {
      type: String,
      required: true,
    },
    replies: {
      type: Array,
      required: true,
    },
    isDiscussionResolved: {
      type: Boolean,
      required: true,
    },
    isDiscussionResolvable: {
      type: Boolean,
      required: true,
    },
    canReply: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['error'],
  data() {
    return {
      submittingId: null,
      answeredId: null,
      submittedCustomAnswer: '',
      selectedIds: [],
      customAnswer: '',
      submittedLabels: [],
      customAnswerResets: 0,
      showOptions: false,
    };
  },
  computed: {
    duoWorkplanAsyncFlowEnabled() {
      return Boolean(this.glFeatures?.duoWorkplanAsyncFlow);
    },
    question() {
      if (!this.duoWorkplanAsyncFlowEnabled) return null;

      const result = parseDuoQuestion(this.note.body);
      if (result.status !== PARSE_STATUS_OK) return null;

      // An open question has nothing to pick from, so the prose above is already the
      // whole interaction.
      const { question } = result;

      return question.type === QUESTION_TYPE_CLOSED ? question : null;
    },
    options() {
      return this.question?.options ?? [];
    },
    // Read back so the answer survives page reloads.
    // Once the thread is resolved, the latest marker wins
    // since anyone can reply but only some can resolve the
    // thread and mark answer as accepted.
    answerReply() {
      if (!this.isDiscussionResolved) return undefined;

      return this.replies.findLast((reply) => parseDuoAnswer(reply.body));
    },
    // Falls back to this session's answer, before the reply reaches the Apollo cache.
    answerId() {
      return this.answeredId ?? parseDuoAnswer(this.answerReply?.body);
    },
    chosenOption() {
      return this.options.find((option) => option.id === this.answerId) ?? null;
    },
    customAnswerText() {
      if (this.answerId !== ANSWER_ID_CUSTOM) return '';

      return this.submittedCustomAnswer || stripDuoAnswerMarker(this.answerReply?.body);
    },
    isMultiple() {
      return Boolean(this.question?.multiple);
    },
    answeredLabels() {
      if (this.isMultiple) {
        if (this.submittedLabels.length) return this.submittedLabels;

        return this.answerReply ? parseDuoAnswerLabels(this.answerReply.body) : [];
      }

      if (this.chosenOption) return [this.chosenOption.label];

      return this.customAnswerText ? [this.customAnswerText] : [];
    },
    isAnswered() {
      return this.answeredLabels.length > 0;
    },
    isResolvedWithoutAnswer() {
      return this.isDiscussionResolved && !this.isAnswered;
    },
    areOptionsVisible() {
      return !this.isResolvedWithoutAnswer || this.showOptions;
    },
    optionsToggleLabel() {
      return this.showOptions
        ? s__('WorkItemDuoQuestion|Hide suggested answers')
        : s__('WorkItemDuoQuestion|Show suggested answers');
    },
    selectedOptions() {
      const picked = this.options.filter((option) => this.selectedIds.includes(option.id));

      return this.customAnswer
        ? [...picked, { id: ANSWER_ID_CUSTOM, label: this.customAnswer }]
        : picked;
    },
    canSubmitSelection() {
      return this.selectedOptions.length > 0 && !this.isSubmitting;
    },
    isSubmitting() {
      return Boolean(this.submittingId);
    },
    // Answering posts a note, so a user who cannot comment is offered nothing to
    // click: the options stay visible, since they record what the agent weighed.
    isDisabled() {
      return this.isSubmitting || !this.canReply || this.isResolvedWithoutAnswer;
    },
    isSubmittingCustomAnswer() {
      return this.submittingId === ANSWER_ID_CUSTOM;
    },
    customResponseDraftKey() {
      return `${this.discussionId}-duo-answer`;
    },
    // Unique per card, since a work item can show several question threads at once.
    customAnswerInputId() {
      return `duo-custom-answer-${this.note.id}`;
    },
    customAnswerInputKey() {
      return `${this.customAnswerInputId}-${this.customAnswerResets}`;
    },
    optionsId() {
      return `duo-question-options-${this.note.id}`;
    },
  },
  methods: {
    answer(option) {
      return this.postAnswer({ id: option.id, body: buildDuoAnswer(option) });
    },
    submitSelection() {
      const { selectedOptions } = this;

      return this.postAnswer({
        id: selectedOptions.map(({ id }) => id).join(','),
        body: buildDuoAnswers(selectedOptions),
        onAnswered: () => {
          this.submittedLabels = selectedOptions.map(({ label }) => label);
          clearDraft(this.customResponseDraftKey);
        },
      });
    },
    submitCustomAnswer(label) {
      return this.postAnswer({
        id: ANSWER_ID_CUSTOM,
        body: buildDuoAnswer({ id: ANSWER_ID_CUSTOM, label }),
        onAnswered: () => {
          this.submittedCustomAnswer = label;
          clearDraft(this.customResponseDraftKey);
        },
      });
    },
    async postAnswer({ id, body, onAnswered }) {
      this.submittingId = id;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: createNoteMutation,
          variables: {
            input: {
              noteableId: this.workItemId,
              discussionId: this.discussionId,
              body,
              internal: this.note.internal,
            },
          },
        });

        if (data?.createNote?.errors?.length) {
          throw new Error(data.createNote.errors.join(', '));
        }

        // Answering and resolving happen together, so a user who cannot resolve only
        // gets the reply posted. Nothing is settled, and the options remain clickable.
        if (!this.isDiscussionResolvable) {
          this.clearSelection();
          return;
        }

        this.answeredId = id;
        onAnswered?.();
        await this.resolveThread();
      } catch (error) {
        this.$emit(
          'error',
          s__(
            'WorkItemDuoQuestion|Something went wrong while sending your answer. Please try again.',
          ),
        );
        Sentry.captureException(error);
      } finally {
        this.submittingId = null;
      }
    },
    clearSelection() {
      this.selectedIds = [];
      clearDraft(this.customResponseDraftKey);
      this.customAnswerResets += 1;
    },
    // A failure here must not read as the answer failing, since the reply is already
    // posted. It does need saying, though: resolving is what signals the question is
    // settled, so an unresolved thread leaves the run waiting.
    async resolveThread() {
      if (this.isDiscussionResolved) return;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: toggleResolveDiscussionMutation,
          variables: { id: this.discussionId, resolve: true },
        });

        const errors = data?.discussionToggleResolve?.errors;
        if (errors?.length) throw new Error(errors.join(', '));
      } catch (error) {
        this.$emit(
          'error',
          s__(
            'WorkItemDuoQuestion|Your answer was posted, but the thread could not be resolved. Resolve it manually so GitLab Duo can continue.',
          ),
        );
        Sentry.captureException(error);
      }
    },
  },
};
</script>

<template>
  <div v-if="question" class="gl-mt-3 gl-flex gl-flex-col gl-gap-3" data-testid="duo-question-note">
    <ul v-if="isAnswered" class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-3 gl-p-0">
      <li
        v-for="(label, index) in answeredLabels"
        :key="index"
        class="gl-flex gl-min-h-8 gl-items-start gl-gap-3 gl-rounded-lg gl-border-1 gl-border-solid gl-border-default gl-bg-subtle gl-px-4 gl-py-3"
        data-testid="duo-answer"
      >
        <gl-icon name="check" variant="success" class="gl-mt-1 gl-shrink-0" />
        <span>{{ label }}</span>
      </li>
    </ul>

    <template v-else>
      <gl-button
        v-if="isResolvedWithoutAnswer"
        :aria-controls="optionsId"
        :aria-expanded="String(showOptions)"
        variant="link"
        class="gl-self-start !gl-text-sm"
        data-testid="duo-question-options-toggle"
        @click="showOptions = !showOptions"
        >{{ optionsToggleLabel }}</gl-button
      >

      <gl-collapse :id="optionsId" :visible="areOptionsVisible">
        <div class="gl-flex gl-flex-col gl-gap-3">
          <duo-multi-select-options
            v-if="isMultiple"
            :options="options"
            :checked-ids="selectedIds"
            :disabled="isDisabled"
            @input="selectedIds = $event"
          />
          <duo-single-select-options
            v-else
            :options="options"
            :disabled="isDisabled"
            :submitting-id="submittingId"
            @select="answer"
          />

          <duo-custom-answer-input
            v-if="canReply && !isResolvedWithoutAnswer"
            :key="customAnswerInputKey"
            :draft-key="customResponseDraftKey"
            :input-id="customAnswerInputId"
            :disabled="isDisabled"
            :submitting="isSubmittingCustomAnswer"
            :multiple="isMultiple"
            @submit="submitCustomAnswer"
            @change="customAnswer = $event"
          />

          <gl-button
            v-if="isMultiple && canReply && !isResolvedWithoutAnswer"
            :disabled="!canSubmitSelection"
            :loading="isSubmitting"
            variant="confirm"
            class="gl-self-start"
            data-testid="duo-question-submit"
            @click="submitSelection"
            >{{ s__('WorkItemDuoQuestion|Submit') }}</gl-button
          >
        </div>
      </gl-collapse>
    </template>
  </div>
</template>
