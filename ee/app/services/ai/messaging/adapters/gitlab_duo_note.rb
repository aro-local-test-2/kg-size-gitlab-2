# frozen_string_literal: true

module Ai
  module Messaging
    module Adapters
      # Delivers the UX for AI flows triggered by @mentioning a service account
      # in a note. Two surfaces share one note lifecycle (started note -> reply);
      # they differ only in who authors the notes:
      #
      #   * @GitLabDuo MR mention (AssistantFlowHandler, via Base#trigger):
      #     authored by the Duo code-review bot.
      #
      #   * Duo Developer @mention (Notes::PostProcessService, via
      #     Base#with_lifecycle_hooks): authored by the flow-trigger SA.
      #
      # Both surfaces log session start and session end on the item's activity
      # log via the framework's default system notes (CreateWorkflowService and
      # UpdateWorkflowStatusService).
      #
      class GitlabDuoNote < Base
        include SafeFormatHelper
        include ::Ai::DuoWorkflows::Concerns::LinkArtifact

        FLOW_CONFIG_ID = 'gitlab_duo_mention_assistant'
        FLOW_CONFIG_SCHEMA_VERSION = 'v1'
        FLOW_VERSION = 'v1'

        def self.adapter_key
          'gitlab_duo_note'
        end

        def self.for_note(note, note_author_id:, force_internal: false)
          new(note_id: note.id, note_author_id: note_author_id, force_internal: force_internal)
        end

        def self.from_callback_context(ctx)
          new(
            note_id: ctx['note_id'],
            note_author_id: ctx['note_author_id'],
            force_internal: ctx['force_internal'] || false
          )
        end

        def initialize(note_id:, note_author_id:, force_internal: false)
          @note_id = note_id
          @note_author_id = note_author_id
          @force_internal = force_internal
        end

        def on_request_received
          note = find_note(@note_id)
          return ServiceResponse.error(message: 'Note not found') unless note
          return ServiceResponse.error(message: 'Noteable not found') unless note.noteable

          ServiceResponse.success
        end

        def on_flow_enqueued(callback_context:, workflow:)
          note = find_note(callback_context['note_id'])
          author = note_author(callback_context)
          return unless note&.noteable && author

          link_triggering_note(workflow, note)

          started_note = ::SystemNotes::IssuablesService.new(
            noteable: note.noteable,
            container: note.project,
            author: author
          ).duo_mention_started(workflow, note.discussion)

          return unless started_note&.persisted?

          workflow.merge_messaging_callback_context!('started_note_id' => started_note.id)
        end

        # Persisted on the workflow; CallbackWorker rebuilds the adapter from it.
        def build_callback_context
          {
            'adapter' => self.class.adapter_key,
            'note_id' => @note_id,
            'note_author_id' => @note_author_id,
            'force_internal' => @force_internal
          }.compact
        end

        # Notes::CreateService returns an unsaved note instead of raising when the note is
        # rejected, so persisted? is what tells CallbackWorker the reply actually landed.
        def deliver_result(callback_context:, message:, workflow:)
          started_note = load_started_note(callback_context)
          destroy_started_note(started_note, callback_context['started_note_id'])
          reply = create_note_on(callback_context, append_session_link(message, workflow))
          link_created_note(workflow, reply)

          reply&.persisted?
        end

        def deliver_error(callback_context:, error:)
          started_note = load_started_note(callback_context)
          workflow = started_note&.duo_metadata&.workflow
          destroy_started_note(started_note, callback_context['started_note_id'])
          error_note = create_note_on(callback_context, error_text(error), error: true)
          link_created_note(workflow, error_note)
        end

        private

        def find_note(note_id)
          ::Note.find_by_id(note_id)
        end

        def note_author(ctx)
          ::User.find_by_id(ctx['note_author_id'])
        end

        # Loads the started note once so callers can reuse it for both workflow
        # lookup and destruction without issuing a second DB query.
        def load_started_note(callback_context)
          note_id = callback_context['started_note_id']
          return unless note_id

          ::Note.find_by_id(note_id)
        end

        def destroy_started_note(started_note, note_id)
          return unless started_note

          # Rescue so a destroy failure is tracked but never blocks the reply
          # that deliver_result/deliver_error posts next.
          started_note.destroy!
        rescue ActiveRecord::RecordNotDestroyed => e
          ::Gitlab::ErrorTracking.track_exception(e, note_id: note_id)
        end

        def append_session_link(message, workflow)
          return message if workflow.nil?

          session_link = safe_format(
            s_("Ai|[View session](%{url})"),
            url: workflow.web_url
          )

          [message.presence, session_link].compact.join("\n\n")
        end

        def create_note_on(callback_context, content, error: false)
          return if content.blank?

          note = find_note(callback_context['note_id'])
          author = note_author(callback_context)
          return unless note&.noteable && author

          # A composite-identity service account's permissions are evaluated
          # against a linked human; terminal delivery runs in CallbackWorker with
          # no request identity, so without this link the SA cannot post the
          # reply. Link it to the original mentioner, mirroring the composite
          # token the legacy self-post path relied on. (No-op for @GitLabDuo,
          # whose bot author is not composite-enforced.)
          link_composite_identity!(author, note.author, note.project.organization)

          # gitlab#606308: a discussion has ONE confidentiality state --
          # Notes::BuildService#new_note overwrites an explicit internal: param
          # with its parent discussion's. So a forced-internal reply to a PUBLIC
          # discussion cannot be threaded: it is posted as a separate internal
          # note, and the mention thread gets a content-free public pointer to
          # it (see #create_pointer_note). An already-internal mention needs no
          # split, and a noteable that cannot hold an internal note at all keeps
          # the ordinary public reply rather than getting no reply.
          thread_into_mention =
            !@force_internal || note.internal? || !noteable_supports_internal_note?(note)

          return internal_reply_denied(note) unless thread_into_mention || can_mark_internal?(note, author)

          reply = ::Notes::CreateService.new(
            note.project,
            author,
            noteable: note.noteable,
            note: content,
            in_reply_to_discussion_id: (note.discussion_id if thread_into_mention),
            internal: @force_internal
          ).execute

          create_pointer_note(note, author, reply, error: error) unless thread_into_mention

          reply
        end

        # The mention thread must still receive an answer even when the
        # substantive reply is forced internal: a short, content-free public
        # pointer threaded into the mention's own discussion, linking to the
        # internal note. Only posted once the internal note actually
        # persisted, so a failed internal note never leaves a dangling
        # pointer (and no findings ever leak into the public thread).
        def create_pointer_note(mention_note, author, internal_note, error:)
          return unless internal_note&.persisted?

          pointer_text = safe_format(
            pointer_format(error),
            url: ::Gitlab::UrlBuilder.build(internal_note)
          )

          pointer_note = ::Notes::CreateService.new(
            mention_note.project,
            author,
            noteable: mention_note.noteable,
            note: pointer_text,
            in_reply_to_discussion_id: mention_note.discussion_id
          ).execute

          return if pointer_note.persisted?

          # The internal note has already persisted, so deliver_result reports
          # success and CallbackWorker will not retry. Without this the mention
          # thread would silently never receive an answer -- and in the forced
          # internal path the pointer is the only reply the mentioner can see.
          ::Gitlab::AppLogger.warn(
            message: "Failed to post pointer note for forced-internal mention reply",
            noteable_type: mention_note.noteable_type,
            noteable_id: mention_note.noteable_id,
            internal_note_id: internal_note.id,
            error: pointer_note.errors.full_messages.join(", ")
          )
        rescue StandardError => e
          # deliver_result keys off the INTERNAL note, which has already
          # persisted by now. Letting this raise would fail the whole delivery,
          # and CallbackWorker's retry would re-run create_note_on and post a
          # second internal note carrying the full review. Track instead.
          ::Gitlab::ErrorTracking.track_exception(
            e,
            noteable_type: mention_note.noteable_type,
            noteable_id: mention_note.noteable_id,
            internal_note_id: internal_note.id
          )
        end

        # Note#noteable_can_have_confidential_note? is private, so mirror its
        # rule. Commit, snippet, design and vulnerability notes can never be
        # internal: forcing one fails validation ("can not be set for this
        # resource"), and once CallbackWorker exhausts its retries the mention
        # gets no answer at all. A public threaded reply is the better failure.
        def noteable_supports_internal_note?(note)
          note.for_issuable? || note.for_wiki_page?
        end

        # Mirrors the check Notes::BuildService#new_note makes before honouring
        # an explicit internal: param. It has to be a PRE-flight check: with no
        # parent discussion to inherit from, a denied internal: is silently
        # dropped and the note saves PUBLIC. Inspecting the saved note is too
        # late -- its side effects have already fired (todos, notification
        # emails, and project webhooks under the non-confidential :note_hooks
        # scope), so a leaked note cannot be un-leaked by destroying it.
        # Failing before the write also lets CallbackWorker retry, which covers
        # the transient case: project_authorizations is refreshed by Sidekiq, so
        # a freshly added service account can briefly lack the permission.
        def can_mark_internal?(note, author)
          ::Ability.allowed?(
            author,
            :mark_note_as_internal,
            ::Note.new(noteable: note.noteable, project: note.project)
          )
        end

        def internal_reply_denied(note)
          ::Gitlab::AppLogger.warn(
            message: "Cannot force an internal mention reply: author cannot mark notes as internal",
            noteable_type: note.noteable_type,
            noteable_id: note.noteable_id,
            project_id: note.project_id
          )

          ::Note.new.tap do |failed|
            failed.errors.add(:base, "Author cannot mark the note as internal")
          end
        end

        # NOTE: safe_format HTML-escapes the format string itself (not only the
        # interpolated arguments), so these strings must avoid apostrophes and
        # other HTML-unsafe characters -- an escaped entity would appear
        # verbatim in the raw note markdown.
        def pointer_format(error)
          if error
            s_(
              "Ai|The task could not be completed. Details are posted in an " \
                "[internal note](%{url}) (visible to project members)."
            )
          else
            s_(
              "Ai|I have posted my response as an [internal note](%{url}) " \
                "(visible to project members)."
            )
          end
        end

        def link_triggering_note(workflow, note)
          return unless note&.persisted?

          result = link_artifact(workflow, note, link_type: :triggered)
          workflow.broadcast_triggering_notes_changed if result&.success?
        rescue StandardError => e
          ::Gitlab::ErrorTracking.track_exception(e, workflow_id: workflow.id)
        end

        def link_created_note(workflow, note)
          return unless note&.persisted?

          link_artifact(workflow, note, link_type: :created)
        end

        def error_text(error)
          case error
          when :service_account_error
            ::Gitlab::Duo::CodeReview::Messages.missing_service_account_error
          when :execute_workflow_failed
            s_("DuoCodeReview|Failed to start the Duo workflow. Please try again.")
          when :flow_failed
            s_("DuoCodeReview|Something went wrong while running the task. Please try again.")
          when :flow_stopped
            s_("DuoCodeReview|The session was stopped before it finished.")
          when :no_response
            s_("DuoCodeReview|The workflow completed but no response was produced. Please try again.")
          when :message_too_long
            s_("DuoCodeReview|Your message is too long for me to process. Shorten it and mention me again.")
          when :invalid_goal, :unsupported_resource_type
            s_("DuoCodeReview|I can't run a code review in this context. " \
              "Please try again on a merge request.")
          when :no_eligible_runner
            format(
              s_("DuoCodeReview|This flow could not start because the project has no runner available. " \
                "It needs an instance runner or a top-level group runner with the `%{tag}` tag and a " \
                "Docker-compatible executor. See the %{link_start}troubleshooting guide%{link_end}."),
              tag: ::Ai::DuoWorkflows::Workflow::WORKLOAD_TAG,
              link_start: "[",
              link_end: "](#{flow_troubleshooting_url})"
            )
          when :namespace_ci_minutes_used_up
            s_("DuoCodeReview|This flow could not start because the namespace has run out of compute minutes. " \
              "Ask someone with billing access to add compute minutes before trying again.")
          else
            s_("DuoCodeReview|Something went wrong. Please try again.")
          end
        end

        def flow_troubleshooting_url
          Rails.application.routes.url_helpers.help_page_url(
            'user/duo_agent_platform/troubleshooting.md',
            anchor: 'a-flows-job-or-session-fails-to-start'
          )
        end
      end
    end
  end
end
