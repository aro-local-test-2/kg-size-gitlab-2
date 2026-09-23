# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CodeReview::ProcessCommentsService, feature_category: :duo_code_review do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:review_bot) { create(:user, :duo_code_review_bot) }

  let(:review_output) { '<review></review>' }

  let(:service) do
    described_class.new(
      user: user,
      merge_request: merge_request,
      review_bot: review_bot,
      review_output: review_output
    )
  end

  # The structured-transport fields default to nil, which is what every XML comment reads.
  def comment_double(**attrs)
    instance_double(
      Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser::Comment,
      **{ severity: nil, end_line: nil, suggestion: nil }.merge(attrs)
    )
  end

  describe '#execute' do
    subject(:execute) { service.execute }

    context 'when review has comments' do
      let(:diff_file) do
        instance_double(Gitlab::Diff::File,
          new_path: 'test.rb',
          old_path: 'test.rb',
          file_path: 'test.rb'
        )
      end

      let(:diff_line) do
        instance_double(Gitlab::Diff::Line,
          old_line: 10,
          new_line: 20,
          text: 'some code',
          removed?: false
        )
      end

      let(:diff_refs) do
        instance_double(Gitlab::Diff::DiffRefs,
          base_sha: 'base',
          start_sha: 'start',
          head_sha: 'head'
        )
      end

      before do
        allow(merge_request).to receive_messages(
          ai_reviewable_diff_files: [diff_file],
          diff_refs: diff_refs
        )

        allow(diff_file).to receive(:diff_lines).and_return([diff_line])

        comment = comment_double(
          file: 'test.rb',
          old_line: 10,
          new_line: 20,
          content: 'Review comment',
          from: "some code\nmore code\neven more code"
        )

        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [comment],
          comments_summary: 'Summary of review'
        )

        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'returns success with draft notes' do
        expect(execute).to be_success
        expect(execute.payload[:draft_notes]).not_to be_empty
      end

      it 'collects metrics correctly' do
        execute

        metrics = execute.payload[:metrics]

        expect(metrics.total_comments).to eq(1)
        expect(metrics.comments_with_valid_path).to eq(1)
        expect(metrics.comments_with_valid_line).to eq(1)
        expect(metrics.comments_by_severity).to be_empty
      end

      context 'with custom instructions in comment' do
        before do
          comment = comment_double(
            file: 'test.rb',
            old_line: 10,
            new_line: 20,
            content: "According to custom instructions in 'Ruby Instructions': Review comment",
            from: "some code"
          )

          parsed_body = instance_double(
            Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
            comments: [comment],
            comments_summary: nil
          )

          allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
            .to receive(:new).and_return(parsed_body)
        end

        it 'increments custom instructions metric' do
          execute

          metrics = execute.payload[:metrics]

          expect(metrics.comments_with_custom_instructions).to eq(1)
        end
      end
    end

    context 'when no comments match diff files' do
      let(:diff_file) { instance_double(Gitlab::Diff::File, new_path: 'test.rb', file_path: 'test.rb') }

      before do
        allow(merge_request).to receive(:ai_reviewable_diff_files).and_return([diff_file])

        comment = comment_double(
          file: 'non_existent.rb',
          old_line: 10,
          new_line: 20,
          content: 'Review comment'
        )

        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [comment],
          comments_summary: nil,
          no_issues_summary: nil
        )

        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'returns success with empty draft notes' do
        expect(execute).to be_success
        expect(execute.payload[:draft_notes]).to be_empty
      end

      it 'returns nothing to comment message' do
        expect(execute.message).to include('I finished my review and found nothing to comment on')
      end

      it 'tracks the no issues event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('find_no_issues_duo_code_review_after_review')

        execute
      end
    end

    context 'with excluded files' do
      let(:excluded_files) { ['excluded.rb'] }

      before do
        allow(service).to receive(:excluded_files).and_return(excluded_files)
        allow(merge_request).to receive(:ai_reviewable_diff_files).and_return([])
      end

      it 'includes exclusion message' do
        expect(execute.message).to include('I do not have access to the following files')
        expect(execute.message).to include('excluded.rb')
      end

      it 'tracks both events' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('find_no_issues_duo_code_review_after_review').ordered
        expect(service).to receive(:track_review_merge_request_event)
          .with('excluded_files_from_duo_code_review').ordered
        execute
      end
    end

    describe 'draft note limit' do
      let(:diff_file) { instance_double(Gitlab::Diff::File) }
      let(:diff_refs) do
        instance_double(Gitlab::Diff::DiffRefs,
          base_sha: 'base',
          start_sha: 'start',
          head_sha: 'head'
        )
      end

      before do
        diff_lines = (1..60).map do |i|
          instance_double(Gitlab::Diff::Line,
            old_line: i,
            new_line: i,
            text: "line #{i}",
            removed?: false
          )
        end
        allow(diff_file).to receive_messages(
          new_path: 'test.rb',
          old_path: 'test.rb',
          file_path: 'test.rb',
          diff_lines: diff_lines
        )
        allow(merge_request).to receive_messages(
          ai_reviewable_diff_files: [diff_file],
          diff_refs: diff_refs
        )
        parsed_comments = (1..60).map do |i|
          comment_double(
            file: 'test.rb',
            old_line: i,
            new_line: i,
            content: "Comment #{i}",
            from: nil
          )
        end
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: parsed_comments,
          comments_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
        allow(service).to receive_messages(
          review_note_already_exists?: false,
          build_summary: 'Summary of 50 comments'
        )
      end

      it 'limits draft notes to DRAFT_NOTES_COUNT_LIMIT' do
        execute
        expect(execute.payload[:draft_notes].count).to eq(50)
      end
    end
  end

  describe '#match_comment_to_diff_line' do
    let(:diff_lines) do
      [
        instance_double(Gitlab::Diff::Line, old_line: 10, new_line: 20, text: 'line 1', removed?: false).tap do |line|
          allow(line).to receive(:text).with(prefix: false).and_return('line 1')
        end,
        instance_double(Gitlab::Diff::Line, old_line: 11, new_line: 21, text: 'line 2', removed?: false).tap do |line|
          allow(line).to receive(:text).with(prefix: false).and_return('line 2')
        end,
        instance_double(Gitlab::Diff::Line, old_line: 12, new_line: 22, text: 'line 3', removed?: false).tap do |line|
          allow(line).to receive(:text).with(prefix: false).and_return('line 3')
        end
      ]
    end

    context 'when matching by line numbers' do
      let(:comment) do
        comment_double(
          old_line: 11,
          new_line: 21,
          from: nil
        )
      end

      it 'finds the correct line' do
        result = service.send(:match_comment_to_diff_line, comment, diff_lines)
        expect(result.new_line).to eq(21)
      end
    end

    context 'when matching by content with enough context' do
      let(:comment) do
        comment_double(
          old_line: nil,
          new_line: nil,
          from: "line 1\nline 2\nline 3"
        )
      end

      it 'finds the line by content matching' do
        result = service.send(:match_comment_to_diff_line, comment, diff_lines)
        expect(result.text).to eq('line 1')
      end

      it 'increments the content matched metric' do
        service.send(:match_comment_to_diff_line, comment, diff_lines)
        expect(service.send(:metrics).comments_line_matched_by_content).to eq(1)
      end
    end

    context 'when content matching fails partway through sequence' do
      let(:comment) do
        comment_double(
          old_line: nil,
          new_line: nil,
          from: "line 1\nline 2\nwrong line that doesn't match"
        )
      end

      it 'falls back to line number matching when sequence fails' do
        result = service.send(:match_comment_to_diff_line, comment, diff_lines)
        expect(result).to be_nil # No line number fallback available

        # Ensure the sequence_matches = false and break logic is hit
        expect(service.send(:metrics).comments_line_matched_by_content).to eq(0)
      end
    end

    context 'when <from> content only partially matches' do
      let(:comment) do
        comment_double(
          old_line: 999,
          new_line: 999,
          from: "line 1\nline 2\nsome random content"
        )
      end

      it 'does not match and falls back to line number logic' do
        result = service.send(:match_comment_to_diff_line, comment, diff_lines)
        expect(result).to be_nil # Invalid line numbers, no match
        expect(service.send(:metrics).comments_line_matched_by_content).to eq(0)
      end
    end

    context 'when sequence matching encounters break condition' do
      let(:comment) do
        comment_double(
          old_line: nil,
          new_line: nil,
          from: "line 2\nline 3\nmismatch on third line"
        )
      end

      it 'breaks out of sequence matching when lines do not match' do
        result = service.send(:match_comment_to_diff_line, comment, diff_lines)
        expect(result).to be_nil
        expect(service.send(:metrics).comments_line_matched_by_content).to eq(0)
      end
    end

    context 'when context is insufficient' do
      let(:comment) do
        comment_double(
          old_line: 11,
          new_line: 21,
          from: "line 2"
        )
      end

      it 'returns the line found by line numbers' do
        result = service.send(:match_comment_to_diff_line, comment, diff_lines)
        expect(result.new_line).to eq(21)
      end
    end
  end

  describe '#build_summary' do
    context 'when parsed body contains a comments_summary' do
      before do
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments_summary: 'Summary of review'
        )
        allow(service).to receive(:parsed_body).and_return(parsed_body)
      end

      it 'returns the summary with exclusion message' do
        result = service.send(:build_summary)
        expect(result).to include('Summary of review')
      end
    end

    context 'when parsed body has no comments_summary' do
      before do
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments_summary: nil
        )
        allow(service).to receive(:parsed_body).and_return(parsed_body)
      end

      it 'returns error message and tracks error event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('encounter_duo_code_review_error_during_review')
        result = service.send(:build_summary)
        expect(result).to eq(::Gitlab::Duo::CodeReview::Messages.could_not_generate_summary_error)
      end
    end
  end

  describe '#build_no_comments_message' do
    let(:diff_file) { instance_double(Gitlab::Diff::File, new_path: 'test.rb', file_path: 'test.rb') }

    before do
      allow(merge_request).to receive(:ai_reviewable_diff_files).and_return([diff_file])
    end

    context 'when review output contains a <summary> tag (LLM found no issues)' do
      let(:review_output) do
        <<~RESPONSE
          <review></review>
          <summary>
          The code changes look good. All tests are passing and best practices are followed.
          </summary>
        RESPONSE
      end

      before do
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [],
          comments_summary: nil,
          no_issues_summary: 'The code changes look good. All tests are passing and best practices are followed.'
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'includes both nothing_to_comment message and summary' do
        result = service.execute

        expect(result).to be_success
        expect(result.message).to include('I finished my review and found nothing to comment on')
        expect(result.message).to include('The code changes look good')
      end

      it 'tracks the no issues event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('find_no_issues_duo_code_review_after_review')

        service.execute
      end
    end

    context 'when review output has no summary' do
      before do
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [],
          comments_summary: nil,
          no_issues_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'falls back to default nothing_to_comment message' do
        result = service.execute

        expect(result).to be_success
        expect(result.message).to include('I finished my review and found nothing to comment on')
      end
    end

    context 'when summary is empty string' do
      let(:review_output) { '<review></review><summary></summary>' }

      before do
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [],
          comments_summary: nil,
          no_issues_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'falls back to default nothing_to_comment message' do
        result = service.execute

        expect(result).to be_success
        expect(result.message).to include('I finished my review and found nothing to comment on')
      end
    end

    context 'when review output contains a <comments_summary> tag (LLM found issues but line matching failed)' do
      let(:review_output) do
        <<~RESPONSE
          <review></review>
          <comments_summary>I left one comment about missing newlines at the end of schema migration files.</comments_summary>
        RESPONSE
      end

      before do
        stub_feature_flags(duo_code_review_previous_discussions: false)

        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [],
          comments_summary: 'I left one comment about missing newlines at the end of schema migration files.'
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'posts the informative message with the comments summary', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.message).to include('unable to post the inline comments due to line number mismatches')
        expect(result.message).to include('My review found:')
        expect(result.message).to include('missing newlines')
        expect(result.message).not_to include('I finished my review and found nothing to comment on')
      end

      it 'tracks the no issues event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('find_no_issues_duo_code_review_after_review')

        service.execute
      end

      context 'when duo_code_review_previous_discussions is enabled' do
        before do
          stub_feature_flags(duo_code_review_previous_discussions: user)
        end

        it 'reports the summary as previous findings rather than a line matching failure',
          :aggregate_failures do
          result = service.execute

          expect(result).to be_success
          expect(result.message).to include('found no new issues')
          expect(result.message).to include('Previous findings:')
          expect(result.message).to include('missing newlines')
          expect(result.message).not_to include('line number mismatches')
          expect(result.message).not_to include('I finished my review and found nothing to comment on')
        end
      end

      context 'when the review produced comments that could not be anchored' do
        let(:comment) do
          comment_double(
            file: 'does/not/exist.rb',
            old_line: nil,
            new_line: 1,
            content: 'Unanchored comment',
            from: nil
          )
        end

        before do
          stub_feature_flags(duo_code_review_previous_discussions: user)

          parsed_body = instance_double(
            Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
            comments: [comment],
            comments_summary: 'I left one comment about missing newlines at the end of schema migration files.'
          )
          allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
            .to receive(:new).and_return(parsed_body)
        end

        it 'still reports the line matching failure', :aggregate_failures do
          result = service.execute

          expect(result).to be_success
          expect(result.message).to include('unable to post the inline comments due to line number mismatches')
          expect(result.message).not_to include('Previous findings:')
        end
      end
    end

    context 'when there are excluded files and summary exists' do
      let(:review_output) do
        <<~RESPONSE
          <review></review>
          <summary>
          Reviewed the accessible files. Code quality is good.
          </summary>
        RESPONSE
      end

      before do
        allow(service).to receive(:excluded_files).and_return(['excluded.rb'])
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [],
          comments_summary: nil,
          no_issues_summary: 'Reviewed the accessible files. Code quality is good.'
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'includes exclusion message, nothing_to_comment message, and summary' do
        result = service.execute

        expect(result).to be_success
        expect(result.message).to include('I do not have access to the following files')
        expect(result.message).to include('excluded.rb')
        expect(result.message).to include('I finished my review and found nothing to comment on')
        expect(result.message).to include('Reviewed the accessible files')
      end
    end

    context 'when there are excluded files and comments_summary exists' do
      let(:review_output) do
        <<~RESPONSE
          <review></review>
          <comments_summary>I left one comment about missing newlines.</comments_summary>
        RESPONSE
      end

      before do
        stub_feature_flags(duo_code_review_previous_discussions: false)

        allow(service).to receive(:excluded_files).and_return(['excluded.rb'])
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [],
          comments_summary: 'I left one comment about missing newlines.'
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'includes exclusion message and the informative message with comments summary', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.message).to include('I do not have access to the following files')
        expect(result.message).to include('excluded.rb')
        expect(result.message).to include('unable to post the inline comments due to line number mismatches')
        expect(result.message).to include('missing newlines')
      end
    end
  end

  describe 'sequence matching edge cases' do
    subject(:execute) { service.execute }

    let(:diff_file) do
      instance_double(Gitlab::Diff::File,
        new_path: 'test.rb',
        old_path: 'test.rb',
        file_path: 'test.rb',
        diff_lines: [
          instance_double(Gitlab::Diff::Line, old_line: 1, new_line: 1, text: 'line 1', removed?: false).tap do |line|
            allow(line).to receive(:text).with(prefix: false).and_return('line 1')
          end,
          instance_double(Gitlab::Diff::Line, old_line: 2, new_line: 2, text: 'line 2', removed?: false).tap do |line|
            allow(line).to receive(:text).with(prefix: false).and_return('line 2')
          end,
          instance_double(Gitlab::Diff::Line, old_line: 3, new_line: 3, text: 'line 3', removed?: false).tap do |line|
            allow(line).to receive(:text).with(prefix: false).and_return('line 3')
          end
        ]
      )
    end

    let(:diff_refs) do
      instance_double(Gitlab::Diff::DiffRefs,
        base_sha: 'base',
        start_sha: 'start',
        head_sha: 'head'
      )
    end

    before do
      allow(merge_request).to receive_messages(
        ai_reviewable_diff_files: [diff_file],
        diff_refs: diff_refs
      )
      allow(service).to receive(:build_summary).and_return('Summary')
    end

    context 'when <from> content has sequence break in middle' do
      before do
        comment = comment_double(
          file: 'test.rb',
          old_line: 999,
          new_line: 999,
          content: 'Comment with partial sequence match',
          from: "line 1\nline 2\nwrong third line"
        )
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [comment],
          comments_summary: nil,
          no_issues_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'handles sequence break correctly and creates no draft notes' do
        execute
        metrics = execute.payload[:metrics]
        expect(metrics.total_comments).to eq(1)
        expect(metrics.comments_with_valid_path).to eq(1)
        expect(metrics.comments_with_valid_line).to eq(0)
        expect(metrics.comments_line_matched_by_content).to eq(0)
        expect(metrics.draft_notes_created).to eq(0)
      end
    end
  end

  describe 'edge case handling for malformed AI responses' do
    subject(:execute) { service.execute }

    let(:diff_file) do
      instance_double(Gitlab::Diff::File,
        new_path: 'test.rb',
        old_path: 'test.rb',
        file_path: 'test.rb',
        diff_lines: [
          instance_double(Gitlab::Diff::Line, old_line: 1, new_line: 1, text: 'line 1', removed?: false),
          instance_double(Gitlab::Diff::Line, old_line: 2, new_line: 2, text: 'line 2', removed?: false)
        ]
      )
    end

    let(:diff_refs) do
      instance_double(Gitlab::Diff::DiffRefs,
        base_sha: 'base',
        start_sha: 'start',
        head_sha: 'head'
      )
    end

    before do
      allow(merge_request).to receive_messages(
        ai_reviewable_diff_files: [diff_file],
        diff_refs: diff_refs
      )
      allow(service).to receive(:build_summary).and_return('Summary')
    end

    context 'when review_output is malformed' do
      let(:review_output) { '<review><comment file="x.rb">unterminated' }

      it 'returns success with empty draft notes' do
        expect(execute).to be_success
        expect(execute.payload[:draft_notes]).to be_empty
      end

      it 'tracks no issues event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('find_no_issues_duo_code_review_after_review')
        execute
      end
    end

    context 'when review_output is empty string' do
      let(:review_output) { '' }

      it 'returns success with empty draft notes' do
        expect(execute).to be_success
        expect(execute.payload[:draft_notes]).to be_empty
      end
    end

    context 'when review_output is malformed object' do
      let(:review_output) { '<unexpected>structure</unexpected>' }

      before do
        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [],
          comments_summary: nil,
          no_issues_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'handles missing comments gracefully' do
        expect(execute).to be_success
        expect(execute.payload[:draft_notes]).to be_empty
      end
    end

    context 'when comments have missing required fields' do
      before do
        comments = [
          comment_double(
            file: 'test.rb',
            old_line: nil,
            new_line: nil,
            content: 'Comment without line info',
            from: nil
          ),
          comment_double(
            file: nil,
            old_line: 1,
            new_line: 1,
            content: 'Comment without file',
            from: nil
          ),
          comment_double(
            file: 'test.rb',
            old_line: 1,
            new_line: 1,
            content: '',
            from: nil
          )
        ]

        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: comments,
          comments_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'filters out invalid comments and processes valid ones' do
        execute

        metrics = execute.payload[:metrics]

        expect(metrics.total_comments).to eq(3)
        expect(metrics.comments_with_valid_path).to eq(2)
        expect(metrics.draft_notes_created).to eq(1)
      end
    end

    context 'when comments reference non-existent files' do
      before do
        comments = [
          comment_double(
            file: 'nonexistent.rb',
            old_line: 1,
            new_line: 1,
            content: 'Comment on missing file',
            from: nil
          ),
          comment_double(
            file: 'test.rb',
            old_line: 1,
            new_line: 1,
            content: 'Valid comment',
            from: nil
          )
        ]

        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: comments,
          comments_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'only processes comments for existing files' do
        execute
        metrics = execute.payload[:metrics]
        expect(metrics.total_comments).to eq(2)
        expect(metrics.comments_with_valid_path).to eq(1)
        expect(metrics.draft_notes_created).to eq(1)
      end
    end

    context 'when comments reference invalid line numbers' do
      before do
        comments = [
          comment_double(
            file: 'test.rb',
            old_line: 999,
            new_line: 999,
            content: 'Comment on non-existent line',
            from: nil
          ),
          comment_double(
            file: 'test.rb',
            old_line: 1,
            new_line: 1,
            content: 'Valid comment',
            from: nil
          )
        ]

        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: comments,
          comments_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'only processes comments with valid line numbers' do
        execute
        metrics = execute.payload[:metrics]
        expect(metrics.total_comments).to eq(2)
        expect(metrics.comments_with_valid_path).to eq(2)
        expect(metrics.comments_with_valid_line).to eq(1)
        expect(metrics.draft_notes_created).to eq(1)
      end
    end

    context 'when response body parser raises an exception' do
      before do
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_raise(StandardError, 'Parser error')
      end

      it 'allows parser errors to propagate' do
        expect { execute }.to raise_error(StandardError, 'Parser error')
      end
    end

    context 'when content matching fails with malformed from content' do
      before do
        comment = comment_double(
          file: 'test.rb',
          old_line: 999,
          new_line: 999,
          content: 'Comment with invalid from content',
          from: "malformed\ncontent\nthat\ndoesn't\nmatch\nanything"
        )

        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: [comment],
          comments_summary: nil,
          no_issues_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'handles content matching failure gracefully' do
        execute
        metrics = execute.payload[:metrics]
        expect(metrics.total_comments).to eq(1)
        expect(metrics.comments_with_valid_path).to eq(1)
        expect(metrics.comments_with_valid_line).to eq(0)
        expect(metrics.comments_line_matched_by_content).to eq(0)
        expect(metrics.draft_notes_created).to eq(0)
      end
    end
  end

  describe 'comprehensive metrics verification' do
    subject(:execute) { service.execute }

    let(:diff_file) do
      instance_double(Gitlab::Diff::File,
        new_path: 'test.rb',
        old_path: 'test.rb',
        file_path: 'test.rb',
        diff_lines: [
          instance_double(Gitlab::Diff::Line, old_line: 1, new_line: 1, text: 'line 1', removed?: false).tap do |line|
            allow(line).to receive(:text).with(prefix: false).and_return('line 1')
          end,
          instance_double(Gitlab::Diff::Line, old_line: 2, new_line: 2, text: 'line 2', removed?: false).tap do |line|
            allow(line).to receive(:text).with(prefix: false).and_return('line 2')
          end,
          instance_double(Gitlab::Diff::Line, old_line: 3, new_line: 3, text: 'line 3', removed?: false).tap do |line|
            allow(line).to receive(:text).with(prefix: false).and_return('line 3')
          end
        ]
      )
    end

    let(:diff_refs) do
      instance_double(Gitlab::Diff::DiffRefs,
        base_sha: 'base',
        start_sha: 'start',
        head_sha: 'head'
      )
    end

    before do
      allow(merge_request).to receive_messages(
        ai_reviewable_diff_files: [diff_file],
        diff_refs: diff_refs
      )
      allow(service).to receive(:build_summary).and_return('Summary')
    end

    context 'with mixed valid and invalid comments' do
      before do
        comments = [
          comment_double(
            file: 'test.rb',
            old_line: 1,
            new_line: 1,
            content: 'Valid comment',
            from: nil
          ),
          comment_double(
            file: 'nonexistent.rb',
            old_line: 1,
            new_line: 1,
            content: 'Invalid file comment',
            from: nil
          ),
          comment_double(
            file: 'test.rb',
            old_line: 999,
            new_line: 999,
            content: 'Invalid line comment',
            from: nil
          ),
          comment_double(
            file: 'test.rb',
            old_line: 2,
            new_line: 2,
            content: "According to custom instructions in 'Ruby Instructions': Another valid comment",
            from: nil
          ),
          comment_double(
            file: 'test.rb',
            old_line: 999,
            new_line: 999,
            content: 'Content matched comment',
            from: "line 1\nline 2\nline 3"
          )
        ]

        parsed_body = instance_double(
          Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
          comments: comments,
          comments_summary: nil
        )
        allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
          .to receive(:new).and_return(parsed_body)
      end

      it 'collects comprehensive metrics correctly' do
        execute

        metrics = execute.payload[:metrics]

        expect(metrics.total_comments).to eq(5)
        expect(metrics.comments_with_valid_path).to eq(4)
        expect(metrics.comments_with_valid_line).to eq(3)
        expect(metrics.comments_with_custom_instructions).to eq(1)
        expect(metrics.comments_line_matched_by_content).to eq(1)
        expect(metrics.draft_notes_created).to eq(3)
      end
    end
  end

  describe 'error handling during draft note creation' do
    subject(:execute) { service.execute }

    let(:diff_file) do
      instance_double(Gitlab::Diff::File,
        new_path: 'test.rb',
        old_path: 'test.rb',
        file_path: 'test.rb',
        diff_lines: [
          instance_double(Gitlab::Diff::Line, old_line: 1, new_line: 1, text: 'line 1', removed?: false)
        ]
      )
    end

    let(:diff_refs) do
      instance_double(Gitlab::Diff::DiffRefs,
        base_sha: 'base',
        start_sha: 'start',
        head_sha: 'head'
      )
    end

    before do
      allow(merge_request).to receive_messages(
        ai_reviewable_diff_files: [diff_file],
        diff_refs: diff_refs
      )

      comment = comment_double(
        file: 'test.rb',
        old_line: 1,
        new_line: 1,
        content: 'Valid comment',
        from: nil
      )

      parsed_body = instance_double(
        Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser,
        comments: [comment],
        comments_summary: nil
      )
      allow(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
        .to receive(:new).and_return(parsed_body)
    end

    context 'when DraftNote creation fails' do
      before do
        allow(DraftNote).to receive(:new).and_raise(StandardError, 'Draft note creation failed')
      end

      it 'allows draft note errors to propagate' do
        expect { execute }.to raise_error(StandardError, 'Draft note creation failed')
      end
    end

    context 'when position creation fails' do
      before do
        allow(Gitlab::Diff::Position).to receive(:new).and_raise(StandardError, 'Position creation failed')
      end

      it 'allows position errors to propagate' do
        expect { execute }.to raise_error(StandardError, 'Position creation failed')
      end
    end
  end

  describe 'structured findings from the deep code review flow' do
    subject(:execute) { service.execute }

    let(:diff_file) do
      instance_double(Gitlab::Diff::File, new_path: 'test.rb', old_path: 'test.rb', file_path: 'test.rb')
    end

    let(:diff_line) do
      instance_double(Gitlab::Diff::Line, old_line: nil, new_line: 20, text: 'some code', removed?: false)
    end

    let(:diff_refs) { instance_double(Gitlab::Diff::DiffRefs, base_sha: 'base', start_sha: 'start', head_sha: 'head') }

    let(:review_output) do
      {
        findings: [
          { file: 'test.rb', new_line: 20, target_code: 'some code', message: 'Structured comment' }
        ],
        summary: 'Structured summary'
      }.to_json
    end

    before do
      allow(merge_request).to receive_messages(ai_reviewable_diff_files: [diff_file], diff_refs: diff_refs)
      allow(diff_file).to receive(:diff_lines).and_return([diff_line])
    end

    context 'when the flag is enabled for the user' do
      before do
        stub_feature_flags(duo_code_review_deep_flow: user)
      end

      it 'parses the JSON findings into draft notes and uses the summary' do
        expect(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser).not_to receive(:new)

        expect(execute).to be_success
        expect(execute.payload[:draft_notes].map(&:note)).to eq(['Structured comment'])
        expect(execute.message).to eq('Structured summary')
      end

      context 'with a suggestion' do
        let(:diff_lines) do
          [20, 21, 22, 30].map do |number|
            instance_double(Gitlab::Diff::Line, old_line: nil, new_line: number, text: 'code', removed?: false)
          end
        end

        let(:finding) do
          { file: 'test.rb', new_line: 20, target_code: 'some code', message: 'Fix', suggestion: "one\ntwo" }
        end

        let(:review_output) { { findings: [finding], summary: 'Summary' }.to_json }

        before do
          allow(diff_file).to receive(:diff_lines).and_return(diff_lines)
        end

        def posted_note
          execute.payload[:draft_notes].sole.note
        end

        it 'replaces the anchored line only when there is no end_line' do
          expect(posted_note).to eq("Fix\n```suggestion:-0+0\none\ntwo\n```")
        end

        context 'when end_line spans lines that are all in the diff' do
          let(:finding) { super().merge(end_line: 22) }

          it 'widens the suggestion to the span' do
            expect(posted_note).to eq("Fix\n```suggestion:-0+2\none\ntwo\n```")
          end
        end

        context 'when end_line is not past the anchored line' do
          let(:finding) { super().merge(end_line: 20) }

          it 'replaces the anchored line only' do
            expect(posted_note).to eq("Fix\n```suggestion:-0+0\none\ntwo\n```")
          end
        end

        context 'when end_line crosses a gap between hunks' do
          let(:finding) { super().merge(end_line: 30) }

          it 'posts the comment without the suggestion' do
            expect(posted_note).to eq('Fix')
          end
        end

        context 'when end_line is past the end of the diff' do
          let(:finding) { super().merge(end_line: 99) }

          it 'posts the comment without the suggestion' do
            expect(posted_note).to eq('Fix')
          end
        end
      end

      context 'with severity' do
        let(:review_output) do
          {
            findings: [
              { file: 'test.rb', new_line: 20, target_code: 'a', message: 'Posted', severity: 'critical' },
              { file: 'test.rb', new_line: 99, target_code: 'b', message: 'No such line', severity: 'major' },
              { file: 'other.rb', new_line: 1, target_code: 'c', message: 'No such file', severity: 'major' }
            ],
            summary: 'Summary'
          }.to_json
        end

        it 'counts only the comments that became draft notes' do
          expect(execute.payload[:metrics].comments_by_severity).to eq('critical' => 1)
        end
      end

      context 'when a re-review has no new findings but earlier threads still need attention' do
        let(:review_output) do
          {
            findings: [],
            summary: '- Looks fine otherwise',
            previous_findings: '- **Still outstanding:** `test.rb`: Unchecked return value.'
          }.to_json
        end

        before do
          stub_feature_flags(duo_code_review_previous_discussions: false)
        end

        it 'reports the previous findings rather than a clean review', :aggregate_failures do
          expect(execute).to be_success
          expect(execute.payload[:draft_notes]).to be_empty
          expect(execute.message).to include('found no new issues')
          expect(execute.message).to include('Previous findings:')
          expect(execute.message).to include('**Still outstanding:** `test.rb`')
          expect(execute.message).not_to include('Looks fine otherwise')
          expect(execute.message).not_to include('line number mismatches')
        end
      end

      context 'when the review output is XML' do
        let(:review_output) { '<review></review>' }

        it 'still uses the XML parser' do
          expect(::Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser)
            .to receive(:new).with(review_output).and_call_original

          expect(execute).to be_success
        end
      end

      context 'when the findings document is malformed' do
        let(:review_output) { '{"summary": "no findings key"}' }

        it 'raises so the caller reports a review error instead of posting a clean review' do
          expect { execute }.to raise_error(::Gitlab::Duo::CodeReview::FindingsParser::Error)
        end
      end
    end

    context 'when the flag is disabled' do
      before do
        stub_feature_flags(duo_code_review_deep_flow: false)
      end

      it 'raises instead of misreading the JSON as an empty XML review' do
        expect { execute }.to raise_error(::Gitlab::Duo::CodeReview::FindingsParser::Error, /disabled/)
      end
    end
  end
end
