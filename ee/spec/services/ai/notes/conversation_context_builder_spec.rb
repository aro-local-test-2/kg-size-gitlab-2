# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Notes::ConversationContextBuilder, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }
  let_it_be(:issue) { create(:issue, project: project) }

  let(:note) { create(:note, project: project, noteable: issue, author: user, note: 'Hello') }

  describe '#build' do
    subject(:context) { described_class.new(note).build.to_s }

    it 'returns a Conversation whose marker states completeness', :aggregate_failures do
      built = described_class.new(note).build

      expect(built).to be_a(::Ai::Messaging::Conversation)
      expect(built.messages.count).to eq(1)
      expect(built.marker.call(0)).to eq(described_class::FULL_THREAD_NOTICE)
    end

    it 'includes the note content in a message block with id' do
      expect(context).to include("<message id=\"#{note.id}\" author=\"@#{user.username}\">\nHello\n</message>")
    end

    it 'marks a complete thread when nothing was trimmed', :aggregate_failures do
      expect(context).to include('All non-system discussion messages through the triggering message are included.')
      expect(context).not_to include('trimmed')
    end

    context 'with notes sharing the discussion_id but belonging to another noteable' do
      let_it_be(:other_issue) { create(:issue, project: project) }

      before do
        create(:note, project: project, noteable: other_issue, author: user,
          note: 'Collision note', discussion_id: note.discussion_id)
      end

      it 'excludes notes from other noteables that collide on discussion_id' do
        expect(context).not_to include('Collision note')
      end
    end

    context 'with multiple notes in the discussion' do
      let_it_be(:other_user) { create(:user) }

      let!(:earlier_note) do
        create(:note, project: project, noteable: issue, author: other_user,
          note: 'Earlier message', discussion_id: note.discussion_id, created_at: note.created_at - 1.minute)
      end

      it 'includes notes through the trigger in chronological order', :aggregate_failures do
        expect(context).to include('Hello')
        expect(context).to include('Earlier message')
        expect(context.index('Earlier message')).to be < context.index('Hello')
      end

      it 'attributes each message to the correct author', :aggregate_failures do
        expect(context).to include("@#{user.username}")
        expect(context).to include("@#{other_user.username}")
      end
    end

    context 'with messages arriving after the trigger', :freeze_time do
      before do
        note
        create(:note, project: project, noteable: issue, author: user,
          note: 'Same timestamp, later ID', discussion_id: note.discussion_id, created_at: note.created_at)
        create(:note, project: project, noteable: issue, author: user,
          note: 'Later message', discussion_id: note.discussion_id, created_at: note.created_at + 1.second)
      end

      it 'ends with the trigger, excluding later messages even at the same timestamp', :aggregate_failures do
        expect(context).to end_with("<message id=\"#{note.id}\" author=\"@#{user.username}\">\nHello\n</message>")
        expect(context).not_to include('Same timestamp, later ID', 'Later message')
      end

      it 'applies the note cap after excluding later messages', :aggregate_failures do
        built = described_class.new(note, max_notes: 1).build

        expect(built.messages.size).to eq(1)
        expect(built.to_s).to include('Hello')
        expect(built.to_s).not_to include('trimmed', 'Later message')
      end
    end

    context 'with an earlier message at the same timestamp', :freeze_time do
      it 'uses the ID to preserve chronological order', :aggregate_failures do
        trigger = create(:note, project: project, noteable: issue, author: user,
          note: 'Trigger', discussion_id: note.discussion_id, created_at: note.created_at)

        built = described_class.new(trigger).build.to_s

        expect(built).to include('Hello', 'Trigger')
        expect(built.index('Hello')).to be < built.index('Trigger')
      end
    end

    context 'with system notes in the discussion' do
      before do
        create(:note, :system, project: project, noteable: issue,
          note: 'added label ~bug', discussion_id: note.discussion_id, created_at: note.created_at - 1.minute)
      end

      it 'excludes system notes' do
        expect(context).not_to include('added label')
      end
    end

    context 'when notes exceed max_notes' do
      subject(:context) { described_class.new(note, max_notes: 2).build.to_s }

      before do
        3.times do |i|
          create(:note, project: project, noteable: issue, author: user,
            note: "Message #{i}", discussion_id: note.discussion_id, created_at: note.created_at - (3 - i).minutes)
        end
      end

      it 'includes an omission notice without a count' do
        expect(context).to include('Earlier messages in this thread were trimmed')
      end

      it 'does not include a specific count of omitted messages' do
        expect(context).not_to match(/\d+ earlier message/)
      end

      it 'includes the discussion ID and URL needed to fetch the rest of the discussion', :aggregate_failures do
        expect(context).to include("Discussion ID: #{note.discussion_id}")
        expect(context).to include("URL: #{Gitlab::UrlBuilder.build(issue)}")
      end

      it 'keeps the notice read-only (no reply-channel instruction)' do
        expect(context).not_to include('reply')
      end

      it 'includes only the most recent messages' do
        expect(context).to include('Message 2')
      end

      it 'excludes older messages beyond max_notes but retains the trigger', :aggregate_failures do
        expect(context).not_to include('Message 0', 'Message 1')
        expect(context).to include('Hello')
      end
    end

    context 'when note has no discussion peers' do
      it 'returns a single message block' do
        blocks = context.scan(/<message/).count
        expect(blocks).to eq(1)
      end
    end

    context 'when the note has no author' do
      before do
        note.update_column(:author_id, non_existing_record_id)
      end

      it 'uses "unknown" as the author' do
        expect(context).to include('@unknown')
      end
    end
  end

  # The generic budgeting mechanics live in conversation_spec; these exercise
  # the builder's marker policy (which notice, when) through the shared object.
  describe 'budgeting the built conversation' do
    let_it_be(:other_user) { create(:user) }

    let(:note) do
      create(:note, project: project, noteable: issue, author: user, note: "Trigger #{'t' * 600}")
    end

    let(:built) { described_class.new(note).build }

    before do
      ["oldest-message #{'o' * 600}", "newer-message #{'n' * 600}"].each_with_index do |body, index|
        create(:note, project: project, noteable: issue, author: other_user,
          note: body, discussion_id: note.discussion_id, created_at: note.created_at - (2 - index).minutes)
      end
    end

    it 'returns the full thread with the complete-thread notice under a generous limit' do
      expect(built.keep_newest_within(10_000)).to eq(built.to_s)
    end

    it 'fits exactly at the to_s boundary' do
      expect(built.keep_newest_within(built.to_s.length)).to eq(built.to_s)
    end

    it 'drops the oldest messages and switches to the truncation notice under a tight limit',
      :aggregate_failures do
      limit = built.to_s.length - 1

      result = built.keep_newest_within(limit)

      expect(result).to start_with(built.marker.call(1))
      expect(result).not_to include('oldest-message')
      expect(result).to include('Trigger')
      expect(result.length).to be <= limit
    end

    it 'accounts for the exact notice each candidate carries', :aggregate_failures do
      # A suffix that fits with its truncation notice exactly at the limit is
      # kept; an up-front full-notice reservation would have rejected it.
      newest = built.messages.last
      notice = built.marker.call(1)
      limit = notice.length + 1 + newest.length

      result = built.keep_newest_within(limit)

      expect(result).to eq("#{notice}\n#{newest}")
      expect(result.length).to eq(limit)
    end

    it 'preserves the trigger at the end of a budgeted developer mention goal', :aggregate_failures do
      render_goal = ->(conversation) do
        Ai::Catalog::GoalTemplates::Developer.resolve(
          event_type: :mention, resource: issue, user_input: conversation,
          params: { note_id: note.id, triggered_by_username: user.username }
        )
      end
      limit = render_goal.call(built.to_s).length - 1

      goal, conversation = built.render_within(limit, &render_goal)

      expect(goal.length).to be <= limit
      expect(conversation).to include('Earlier messages in this thread were trimmed')
      expect(conversation).not_to include('oldest-message')
      expect(goal).to end_with("#{built.messages.last}\n</conversation>")
    end

    it 'returns nil when not even the newest message fits' do
      expect(built.keep_newest_within(10)).to be_nil
    end

    context 'when the note cap already dropped messages' do
      before do
        3.times do |i|
          create(:note, project: project, noteable: issue, author: user,
            note: "Message #{i}", discussion_id: note.discussion_id, created_at: note.created_at - (3 - i).seconds)
        end
      end

      it 'keeps the truncation notice even when everything fits the budget', :aggregate_failures do
        result = described_class.new(note, max_notes: 2).build.keep_newest_within(10_000)

        expect(result).to include('Earlier messages in this thread were trimmed')
        expect(result).to include('Message 2')
      end
    end
  end
end
