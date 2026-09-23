# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::GoalTemplates::Developer, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project, :small_repo) }
  let_it_be(:issue) { create(:issue, project: project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  let(:user_input) { 'Please help me with this task' }
  let(:triggered_by_username) { 'john_doe' }

  describe '.resolve' do
    context 'with init_execution_env event type' do
      it 'returns an interpolated goal covering all required content', :aggregate_failures do
        result = described_class.resolve(
          event_type: :init_execution_env,
          resource: project,
          user_input: nil
        )

        expect(result).to include(project.full_path)
        expect(result).to include(project.default_branch_or_main)
        expect(result).to include('.gitlab/duo/agent-config.yml')
        expect(result).to include('image')
        expect(result).to include('setup_script')
        expect(result).to include('cache')
        expect(result).to include('network_policy')
        expect(result.bytesize).to be < 16.kilobytes
      end
    end

    context 'with mention event type' do
      let(:params) { { note_id: 42, triggered_by_username: triggered_by_username } }

      it 'returns a goal from the mention template with conversation context' do
        result = described_class.resolve(
          event_type: :mention, resource: issue, user_input: user_input, params: params
        )

        expect(result).to include('<conversation>')
        expect(result).to include(user_input)
        expect(result).to include('<gitlab_context>')
      end

      it 'includes the triggering username in the goal', :aggregate_failures do
        result = described_class.resolve(
          event_type: :mention, resource: issue, user_input: user_input, params: params
        )

        expect(result).to include("Requesting user: @#{triggered_by_username}")
        expect(result).to include(
          "delivered automatically to this discussion. Include @#{triggered_by_username} in it to notify them."
        )
        expect(result).to include("assign it to @#{triggered_by_username}")
      end

      it 'includes the correct resource name for a merge request' do
        result = described_class.resolve(
          event_type: :mention, resource: merge_request, user_input: user_input, params: params
        )

        expect(result).to include("Merge request: #{Gitlab::UrlBuilder.build(merge_request)}#note_42")
      end

      it 'handles missing triggered_by_username gracefully' do
        result = described_class.resolve(
          event_type: :mention, resource: issue, user_input: user_input, params: { note_id: 42 }
        )

        expect(result).to include("Requesting user: @\n")
      end
    end

    context 'with assign event type' do
      let(:params) { { triggered_by_username: triggered_by_username } }

      it 'returns the issue template for an Issue' do
        result = described_class.resolve(
          event_type: :assign, resource: issue, user_input: user_input, params: params
        )

        expect(result).to include("@#{triggered_by_username} assigned you to solve the following issue:")
        expect(result).to include(Gitlab::UrlBuilder.build(issue))
        expect(result).to include("@mention @#{triggered_by_username} in a comment on the issue")
      end

      it 'returns the work item template with correct resource name for a WorkItem' do
        work_item = create(:work_item, project: project)
        result = described_class.resolve(
          event_type: :assign, resource: work_item, user_input: user_input, params: params
        )

        expect(result).to include("@#{triggered_by_username} assigned you to solve the following work item:")
        expect(result).to include(Gitlab::UrlBuilder.build(work_item))
      end

      it 'returns the MR assign template for a MergeRequest' do
        result = described_class.resolve(
          event_type: :assign, resource: merge_request, user_input: user_input, params: params
        )

        expect(result).to include("@#{triggered_by_username} assigned you to a merge request:")
        expect(result).to include('Fetch the merge request details, its diffs, pipeline status')
        expect(result).to include(Gitlab::UrlBuilder.build(merge_request))
        expect(result).to include("@mention @#{triggered_by_username} in a comment")
      end
    end

    context 'with assign_reviewer event type' do
      let(:params) { { triggered_by_username: triggered_by_username } }

      it 'returns the MR review template for a MergeRequest' do
        result = described_class.resolve(
          event_type: :assign_reviewer, resource: merge_request, user_input: user_input, params: params
        )

        expect(result).to include("@#{triggered_by_username} requested your review on a merge request:")
        expect(result).to include(Gitlab::UrlBuilder.build(merge_request))
        expect(result).to include("@mention @#{triggered_by_username} in a comment")
      end
    end

    context 'with merge_request event type' do
      it 'returns the merged merge request template attributing the author', :aggregate_failures do
        result = described_class.resolve(
          event_type: :merge_request, resource: merge_request, user_input: user_input,
          params: { action: 'merged', session_ids: [123, 456] }
        )

        expect(result).to include('has just been merged')
        expect(result).to include(Gitlab::UrlBuilder.build(merge_request))
        expect(result).to include('session IDs: 123, 456')
        expect(result).to include('.gitlab/duo/agent-config.yml')
        expect(result).to include('AGENTS.md')
        expect(result).to include('CLAUDE.md')
        expect(result).to include('duo/distill/')
        expect(result).to include("#{Gitlab::UrlBuilder.build(project)}/-/automate/agent-sessions/")
        expect(result).to include("--assignee #{merge_request.author.username}")
        expect(result).to include('work_items/613978')
        expect(result.bytesize).to be < 16.kilobytes
      end

      context 'when the merge request author has been deleted' do
        it 'handles nil author gracefully', :aggregate_failures do
          allow(merge_request).to receive(:author).and_return(nil)

          result = described_class.resolve(
            event_type: :merge_request, resource: merge_request, user_input: user_input,
            params: { action: 'merged', session_ids: [123] }
          )

          expect(result).to include('has just been merged')
          expect(result).to include('Do not request review from anyone')
        end
      end

      context 'when no metrics exist and no reviewers' do
        it 'does not request a reviewer', :aggregate_failures do
          allow(merge_request).to receive(:metrics).and_return(nil)

          result = described_class.resolve(
            event_type: :merge_request, resource: merge_request, user_input: user_input,
            params: { action: 'merged', session_ids: [123] }
          )

          expect(result).to include('Do not request review from anyone')
          expect(result).not_to include('--reviewer')
        end
      end

      context 'when the merge request has been merged by the author' do
        before do
          merge_request.ensure_metrics!
          merge_request.metrics.update!(merged_by: merge_request.author)
        end

        after do
          merge_request.association(:metrics).reset
        end

        it 'does not request a reviewer when no other reviewers exist', :aggregate_failures do
          result = described_class.resolve(
            event_type: :merge_request, resource: merge_request, user_input: user_input,
            params: { action: 'merged', session_ids: [123] }
          )

          expect(result).to include('Do not request review from anyone')
          expect(result).not_to include('--reviewer')
        end
      end

      context 'when the author merged their own MR but it has other reviewers' do
        let_it_be(:reviewer_user) { create(:user) }
        let_it_be(:mr_with_reviewer) do
          create(:merge_request, source_project: project, target_project: project,
            source_branch: 'with-reviewer').tap do |mr|
            mr.ensure_metrics!
            mr.metrics.update!(merged_by: mr.author)
            create(:merge_request_reviewer, merge_request: mr, reviewer: reviewer_user)
          end
        end

        it 'picks a reviewer from the merged MR reviewer list', :aggregate_failures do
          result = described_class.resolve(
            event_type: :merge_request, resource: mr_with_reviewer, user_input: user_input,
            params: { action: 'merged', session_ids: [123] }
          )

          expect(result).to include(
            "Request review from `#{reviewer_user.username}` using `--reviewer #{reviewer_user.username}`."
          )
        end
      end

      context 'when the author merged their own MR and only reviewer is the author' do
        let_it_be(:mr_self_reviewed) do
          create(:merge_request, source_project: project, target_project: project,
            source_branch: 'self-reviewed').tap do |mr|
            mr.ensure_metrics!
            mr.metrics.update!(merged_by: mr.author)
            create(:merge_request_reviewer, merge_request: mr, reviewer: mr.author)
          end
        end

        it 'does not request a reviewer', :aggregate_failures do
          result = described_class.resolve(
            event_type: :merge_request, resource: mr_self_reviewed, user_input: user_input,
            params: { action: 'merged', session_ids: [123] }
          )

          expect(result).to include('Do not request review from anyone')
          expect(result).not_to include('--reviewer')
        end
      end

      context 'when the merge request has been merged by a different user' do
        let_it_be(:merger) { create(:user) }

        before do
          merge_request.ensure_metrics!
          merge_request.metrics.update!(merged_by: merger)
        end

        after do
          merge_request.association(:metrics).reset
        end

        it 'assigns to author and requests review from the merger', :aggregate_failures do
          result = described_class.resolve(
            event_type: :merge_request, resource: merge_request, user_input: user_input,
            params: { action: 'merged', session_ids: [123] }
          )

          expect(result).to include("--assignee #{merge_request.author.username}")
          expect(result).to include("Request review from `#{merger.username}` using `--reviewer #{merger.username}`.")
        end
      end
    end

    context 'when resource is nil' do
      it 'raises ArgumentError' do
        expect do
          described_class.resolve(
            event_type: :assign, resource: nil, user_input: user_input
          )
        end.to raise_error(ArgumentError, /resource must not be nil/)
      end
    end

    context 'with unsupported event type' do
      it 'raises ArgumentError' do
        expect do
          described_class.resolve(
            event_type: :pipeline_hooks, resource: issue, user_input: user_input
          )
        end.to raise_error(ArgumentError, /Unsupported event type.*:pipeline_hooks/)
      end
    end

    context 'when user input contains format string sequences' do
      let(:malicious_input) { 'Fix %{resource_url} and %{unknown_key} please' }
      let(:params) { { note_id: 42, triggered_by_username: triggered_by_username } }

      it 'preserves literal %{...} sequences in user input without raising' do
        result = described_class.resolve(
          event_type: :mention, resource: issue, user_input: malicious_input, params: params
        )

        expect(result).to include('%{unknown_key}')
        expect(result).to include('<conversation>')
        expect(result).to include(malicious_input)
      end

      it 'does not let user input substitute resource_url in template vars' do
        result = described_class.resolve(
          event_type: :mention, resource: issue, user_input: malicious_input, params: params
        )

        # The %{resource_url} in user input should remain literal, not be double-substituted
        expect(result).to include("Fix %{resource_url} and %{unknown_key} please")
      end
    end
  end

  describe '.handler_for' do
    it 'returns Mention for :mention' do
      expect(described_class.handler_for(:mention, issue))
        .to eq(Ai::Catalog::GoalTemplates::Developer::Mention)
    end

    it 'returns AssignIssue for :assign with non-MR resource' do
      expect(described_class.handler_for(:assign, issue)).to eq(Ai::Catalog::GoalTemplates::Developer::AssignIssue)
    end

    it 'returns AssignMergeRequest for :assign with MergeRequest' do
      expect(described_class.handler_for(:assign, merge_request))
        .to eq(Ai::Catalog::GoalTemplates::Developer::AssignMergeRequest)
    end

    it 'returns AssignMergeRequestReview for :assign_reviewer' do
      expect(described_class.handler_for(:assign_reviewer, merge_request))
        .to eq(Ai::Catalog::GoalTemplates::Developer::AssignMergeRequestReview)
    end

    it 'returns MergedMergeRequest for the merged :merge_request action' do
      expect(described_class.handler_for(:merge_request, merge_request, { action: 'merged' }))
        .to eq(Ai::Catalog::GoalTemplates::Developer::MergedMergeRequest)
    end

    it 'raises for a merge_request action other than merged' do
      expect { described_class.handler_for(:merge_request, merge_request, { action: 'approved' }) }
        .to raise_error(ArgumentError, /Unsupported merge request action/)
    end

    it 'raises for a merge_request event with no action' do
      expect { described_class.handler_for(:merge_request, merge_request) }
        .to raise_error(ArgumentError, /Unsupported merge request action/)
    end

    it 'returns InitExecutionEnv for :init_execution_env' do
      expect(described_class.handler_for(:init_execution_env, project))
        .to eq(Ai::Catalog::GoalTemplates::Developer::InitExecutionEnv)
    end

    it 'raises ArgumentError for unknown event type' do
      expect { described_class.handler_for(:unknown, issue) }
        .to raise_error(ArgumentError, /Unsupported event type/)
    end
  end

  describe '.resource_display_name' do
    it 'returns "merge request" for MergeRequest' do
      expect(described_class.resource_display_name(merge_request)).to eq('merge request')
    end

    it 'returns "issue" for Issue' do
      expect(described_class.resource_display_name(issue)).to eq('issue')
    end

    it 'returns "work item" for WorkItem' do
      resource = build(:work_item, project: project)
      expect(described_class.resource_display_name(resource)).to eq('work item')
    end

    it 'returns a humanized fallback for unknown resource types' do
      resource = build(:project)
      expect(described_class.resource_display_name(resource)).to eq('project')
    end
  end
end
