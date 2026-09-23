# frozen_string_literal: true

module Gitlab
  module WorkItems
    # Rewrites the machine-readable question payload the workplan flow attaches to a
    # note into prose, for the notification emails that cannot run the work item UI's
    # parser. The page hides the payload with CSS and re-renders it as an interactive
    # card; email has neither.
    # See https://gitlab.com/gitlab-org/gitlab/-/issues/627212.
    module DuoQuestionEmailBody
      # RE2 rather than Ruby regexes: a note body is untrusted input, and these
      # lazy quantifiers backtrack quadratically on a body full of unclosed
      # fences. RE2 has no backtracking, so no replacement limit is needed.
      #
      # Stricter than FENCE_RE and MARKER_RE in
      # ee/app/assets/javascripts/work_items/utils/duo_question.js: these scan a
      # whole body rather than one already-isolated note, so both are anchored.
      FENCE_REGEX = ::Gitlab::UntrustedRegexp.new(
        '(?s)^ {0,3}```json:duo-question[^\n]*\n(?P<payload>.*?)^ {0,3}```[ \t]*(?:\n|\z)',
        multiline: true
      ).freeze
      MARKER_REGEX = ::Gitlab::UntrustedRegexp.new(
        '(?s)^ {0,3}<!--\s*duo:options\s*(?P<content>.*?)-->[ \t]*(?:\n|\z)',
        multiline: true
      ).freeze
      MARKER_ARRAY_REGEX = ::Gitlab::UntrustedRegexp.new('(?s)(?P<array>\[.*?\])').freeze

      # Left as Ruby regexes: neither can backtrack, and both run on the small
      # slice a marker match already bounded.
      MARKER_RECOMMENDED_REGEX = /duo:recommended\s*(?<index>\d+)/
      MARKER_MULTIPLE_REGEX = /duo:multiple\b/

      # Cheap enough to run on every note email, and skips the regexes for the
      # overwhelming majority of bodies that carry no payload at all.
      PAYLOAD_HINTS = ['json:duo-question', 'duo:options'].freeze

      QUESTION_TYPE_CLOSED = 'closed'

      # Kept in step with MAX_OPTIONS in duo_question.js, and applied to the
      # options as written rather than the ones that survive validation, because
      # that is where the work item UI applies it.
      MAX_OPTIONS = 10

      # Mirror the work item UI's option validation.
      MAX_LABEL_LENGTH = 200
      MAX_DESCRIPTION_LENGTH = 500

      class << self
        def rewrite(note, format: :html)
          body = note.note
          return body unless PAYLOAD_HINTS.any? { |hint| body.to_s.include?(hint) }
          return body unless duo_flow_authored?(note)

          rewrite_payloads(body, format)
        end

        private

        # Workflow links are written after notification enqueue, so gate on the committed author.
        # ItemConsumer restricts this to flow service accounts; disabled flows remain eligible
        # so their existing questions stay readable.
        def duo_flow_authored?(note)
          ::Gitlab::SafeRequestStore.fetch([:duo_question_flow_author, note.author_id]) do
            ::Ai::Catalog::ItemConsumer.for_service_account(note.author_id).exists?
          end
        end

        # Remove unrenderable payloads because the preceding prose contains the question.
        def rewrite_payloads(body, format)
          rewritten = FENCE_REGEX.replace_gsub(body) do |match|
            prose_for(payload_from_fence(match[:payload]), format)
          end
          rewritten = MARKER_REGEX.replace_gsub(rewritten) do |match|
            prose_for(payload_from_marker(match[:content]), format)
          end

          return body if rewritten == body

          rewritten.rstrip
        end

        def parse_json(raw)
          ::Gitlab::Json::SafeParser.parse(raw.to_s)
        rescue ::JSON::ParserError
          nil
        end

        def payload_from_fence(raw)
          payload = parse_json(raw)
          return unless payload.is_a?(Hash)

          options = payload['options'].is_a?(Array) ? payload['options'] : []

          {
            type: payload['type'],
            multiple: payload['multiple'] == true,
            declared_count: options.size,
            options: options.filter_map { |option| normalize_option(option) }
          }
        end

        # The marker form carries bare labels, and `duo:recommended` is a
        # 1-based index into them rather than a flag on the option itself.
        def payload_from_marker(content)
          labels = parse_json(MARKER_ARRAY_REGEX.match(content)&.[](:array))
          return unless labels.is_a?(Array)

          recommended = content[MARKER_RECOMMENDED_REGEX, :index].to_i

          {
            type: QUESTION_TYPE_CLOSED,
            multiple: MARKER_MULTIPLE_REGEX.match?(content),
            declared_count: labels.size,
            options: labels.each_with_index.filter_map do |label, index|
              normalize_option({ 'label' => label, 'recommended' => index + 1 == recommended })
            end
          }
        end

        def normalize_option(option)
          return unless option.is_a?(Hash)

          label = option['label']
          return unless label.is_a?(String) && label.present?

          return if label.match?(/[\r\n]/)
          return if label.length > MAX_LABEL_LENGTH

          {
            label: label.squish,
            description: normalize_description(option['description']),
            recommended: option['recommended'] == true
          }
        end

        def normalize_description(description)
          return unless description.is_a?(String)

          description.squish.presence&.slice(0, MAX_DESCRIPTION_LENGTH)
        end

        def prose_for(payload, format)
          return '' unless renderable?(payload)

          bullets = payload[:options].map { |option| bullet_for(option, format) }

          "#{instruction(payload[:multiple])}\n\n#{bullets.join("\n")}\n"
        end

        def renderable?(payload)
          return false if payload.nil?
          return false if payload[:type] != QUESTION_TYPE_CLOSED
          return false if payload[:declared_count] > MAX_OPTIONS

          payload[:options].present?
        end

        def instruction(multiple)
          if multiple
            s_('WorkItemDuoQuestion|Choose one or more of these options, or answer in your own words:')
          else
            s_('WorkItemDuoQuestion|Choose one of these options, or answer in your own words:')
          end
        end

        def bullet_for(option, format)
          bullet = "- **#{escape(option[:label], format)}**"
          bullet += " (#{s_('WorkItemDuoQuestion|Recommended')})" if option[:recommended]
          bullet += ": #{escape(option[:description], format)}" if option[:description].present?
          bullet
        end

        # Prevents model-authored option text from becoming active Markdown, but
        # only for the part that is rendered as Markdown. The text part is emitted
        # byte for byte, so escaping there shows the reader backslashes nothing
        # downstream will consume, and there is no Markdown to inject into.
        def escape(text, format)
          return text unless format == :html

          ::GLFMMarkdown.escape_commonmark_inline(text)
        end
      end
    end
  end
end
