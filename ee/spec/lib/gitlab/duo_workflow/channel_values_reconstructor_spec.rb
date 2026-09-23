# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::DuoWorkflow::ChannelValuesReconstructor, feature_category: :duo_agent_platform do
  # Mirror the gateway wire format: data is zlib-compressed JSON.
  def blob(channel:, version:, value:, step_action: 'conversation', thread_ts: 'ts-1')
    instance_double(
      Ai::DuoWorkflows::CheckpointBlob,
      channel: channel,
      version: version,
      step_action: step_action,
      thread_ts: thread_ts,
      data: Zlib::Deflate.deflate(Gitlab::Json.dump(value))
    )
  end

  subject(:channel_values) { described_class.new(blobs).channel_values }

  context 'with a list (append) channel' do
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
        blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }, { 'content' => 'c' }])
      ]
    end

    it 'concatenates the deltas in version order' do
      expect(channel_values).to eq(
        'ui_chat_log' => [{ 'content' => 'a' }, { 'content' => 'b' }, { 'content' => 'c' }]
      )
    end
  end

  context 'with a dict-of-list channel' do
    let(:blobs) do
      [
        blob(channel: 'conversation_history', version: '1', value: { 'agent' => [{ 'm' => 1 }] }),
        blob(channel: 'conversation_history', version: '2', value: { 'agent' => [{ 'm' => 2 }] })
      ]
    end

    it 'appends each key tail to the accumulated list' do
      expect(channel_values).to eq(
        'conversation_history' => { 'agent' => [{ 'm' => 1 }, { 'm' => 2 }] }
      )
    end
  end

  context 'with a compaction delta' do
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
        blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }]),
        blob(channel: 'ui_chat_log', version: '3', value: [{ 'content' => 'compacted' }],
          step_action: 'compaction')
      ]
    end

    it 'replaces the accumulated value with the full compacted value' do
      expect(channel_values).to eq('ui_chat_log' => [{ 'content' => 'compacted' }])
    end
  end

  context 'with a self-contained group (compaction snapshot then conversation deltas)' do
    # Mirrors AIGW self-contained groups: a group opens with a full compaction
    # snapshot, then later steps append conversation deltas onto it.
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', step_action: 'compaction',
          value: [{ 'content' => 'seed a' }, { 'content' => 'seed b' }]),
        blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'c' }]),
        blob(channel: 'ui_chat_log', version: '3', value: [{ 'content' => 'd' }])
      ]
    end

    it 'seeds from the snapshot and appends the later deltas' do
      expect(channel_values).to eq(
        'ui_chat_log' => [
          { 'content' => 'seed a' }, { 'content' => 'seed b' },
          { 'content' => 'c' }, { 'content' => 'd' }
        ]
      )
    end
  end

  context 'with deltas before and after a mid-chain compaction' do
    # Anchoring starts the fold at the last compaction, so the pre-compaction
    # delta is never replayed; the result is the snapshot plus what follows it.
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'pre' }]),
        blob(channel: 'ui_chat_log', version: '2', step_action: 'compaction',
          value: [{ 'content' => 'snapshot' }]),
        blob(channel: 'ui_chat_log', version: '3', value: [{ 'content' => 'post' }])
      ]
    end

    it 'starts from the last compaction and ignores earlier deltas' do
      expect(channel_values).to eq(
        'ui_chat_log' => [{ 'content' => 'snapshot' }, { 'content' => 'post' }]
      )
    end
  end

  context 'with duplicate (channel, version) blobs' do
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }])
      ]
    end

    it 'collapses duplicates so the delta is applied once' do
      expect(channel_values).to eq('ui_chat_log' => [{ 'content' => 'a' }])
    end
  end

  context 'with a conversation and a compaction blob that share a version' do
    # A force_rewrite can store both for one (channel, version). #channel_values
    # anchors on the compaction (the full value), so it wins here.
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
        blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'delta' }]),
        blob(channel: 'ui_chat_log', version: '2', step_action: 'compaction',
          value: [{ 'content' => 'snapshot' }])
      ]
    end

    it 'anchors on the same-version compaction snapshot' do
      expect(channel_values).to eq('ui_chat_log' => [{ 'content' => 'snapshot' }])
    end
  end

  context 'with a same-version collision whose rows are not adjacent' do
    # The winning v1 compaction arrives after v2. It anchors at the v1 slot, so the v2
    # delta still applies on top of it. Anchoring at the later slot would drop that delta.
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'stale' }]),
        blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }]),
        blob(channel: 'ui_chat_log', version: '1', step_action: 'compaction',
          value: [{ 'content' => 'snapshot' }])
      ]
    end

    it 'anchors at the version first occurrence and keeps the later delta' do
      expect(channel_values).to eq('ui_chat_log' => [{ 'content' => 'snapshot' }, { 'content' => 'b' }])
    end
  end

  context 'with the same version repeated across different thread_ts' do
    # Defense-in-depth: dedup keys on (thread_ts, version), not version alone, so
    # a version number that legitimately repeats across groups isn't mistaken for
    # a same-thread retry and dropped.
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }], thread_ts: 'ts-1'),
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'b' }], thread_ts: 'ts-2')
      ]
    end

    it 'keeps both blobs instead of collapsing them as a retry' do
      expect(channel_values).to eq('ui_chat_log' => [{ 'content' => 'a' }, { 'content' => 'b' }])
    end
  end

  context 'with versions that reset across thread_ts' do
    # If DWS ever reset channel_version per group, a numeric sort would place
    # thread B's v1 before thread A's v2, breaking the session's real order.
    # Ordering by chain position (array order) keeps it chronological anyway.
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a1' }], thread_ts: 'ts-a'),
        blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'a2' }], thread_ts: 'ts-a'),
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'b1' }], thread_ts: 'ts-b'),
        blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b2' }], thread_ts: 'ts-b')
      ]
    end

    it 'keeps chain order instead of interleaving by numeric version' do
      expect(channel_values).to eq(
        'ui_chat_log' => [
          { 'content' => 'a1' }, { 'content' => 'a2' }, { 'content' => 'b1' }, { 'content' => 'b2' }
        ]
      )
    end
  end

  context 'with versions that sort lexically out of order' do
    # Ordering is by chain position (array order), not by comparing version
    # strings, so "10" naturally follows "9" here without a numeric sort.
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '9', value: [{ 'content' => '9' }]),
        blob(channel: 'ui_chat_log', version: '10', value: [{ 'content' => '10' }])
      ]
    end

    it 'keeps chain order so "10" follows "9"' do
      expect(channel_values).to eq(
        'ui_chat_log' => [{ 'content' => '9' }, { 'content' => '10' }]
      )
    end
  end

  context 'with multiple channels' do
    let(:blobs) do
      [
        blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
        blob(channel: 'context', version: '1', value: { 'goal' => 'x' }, step_action: 'compaction')
      ]
    end

    it 'reconstructs each channel independently' do
      expect(channel_values).to eq(
        'ui_chat_log' => [{ 'content' => 'a' }],
        'context' => { 'goal' => 'x' }
      )
    end
  end

  context 'with no blobs' do
    let(:blobs) { [] }

    it { is_expected.to eq({}) }
  end

  context 'with a corrupted blob' do
    let(:corrupt_blob) do
      instance_double(
        Ai::DuoWorkflows::CheckpointBlob,
        channel: 'ui_chat_log', version: '2', step_action: 'conversation', thread_ts: 'ts-1', data: 'not zlib'
      )
    end

    let(:blobs) do
      [blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]), corrupt_blob]
    end

    it 'raises so the read fails rather than returning inconsistent values' do
      expect { channel_values }.to raise_error(described_class::CorruptBlobError)
    end
  end

  context 'with a blob that inflates to bytes that are not JSON' do
    let(:msgpack_blob) do
      instance_double(
        Ai::DuoWorkflows::CheckpointBlob,
        channel: 'ui_chat_log', version: '2', step_action: 'conversation', thread_ts: 'ts-1',
        data: Zlib::Deflate.deflate("\x8b\xa4plan\x90".b)
      )
    end

    let(:blobs) { [msgpack_blob] }

    it 'raises without the payload in the message', :aggregate_failures do
      expect { channel_values }.to raise_error(described_class::CorruptBlobError) do |error|
        expect(error.message).to eq('Failed to decode checkpoint blob')
        expect(error.cause).to be_a(JSON::ParserError)
      end
    end
  end

  describe '#channel_history' do
    let(:ancestry) { { 'ts-1' => nil, 'ts-2' => 'ts-1' } }
    let(:alternatives) { {} }

    # Every entry is stamped with the checkpoint that introduced it; blobs default
    # to the chain root, whose parent_ts is nil.
    def message(content, thread_ts: 'ts-1', parent_ts: nil)
      { 'content' => content, 'thread_ts' => thread_ts, 'parent_ts' => parent_ts }
    end

    subject(:history) do
      described_class.new(blobs).channel_history('ui_chat_log', ancestry, alternatives)
    end

    context 'with deltas around a mid-chain compaction' do
      # Unlike #channel_values (which anchors at the last compaction), history keeps
      # the pre-compaction deltas, and the summary card the snapshot adds.
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }]),
          blob(channel: 'ui_chat_log', version: '3', step_action: 'compaction',
            value: [{ 'content' => 'summary' }]),
          blob(channel: 'ui_chat_log', version: '4', value: [{ 'content' => 'c' }])
        ]
      end

      it 'keeps every conversation delta and the compaction summary in place' do
        expect(history).to eq([message('a'), message('b'), message('summary'), message('c')])
      end
    end

    context 'with messages introduced only by the compaction-triggering checkpoint' do
      # The gateway re-seeds every channel as a full snapshot on the step that
      # triggers a compaction, so that step writes no conversation delta: 'c' and
      # 'd' exist nowhere else.
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }]),
          blob(channel: 'ui_chat_log', version: '3', thread_ts: 'ts-2', step_action: 'compaction',
            value: [{ 'content' => 'a' }, { 'content' => 'b' }, { 'content' => 'c' }, { 'content' => 'd' }]),
          blob(channel: 'ui_chat_log', version: '4', thread_ts: 'ts-2', value: [{ 'content' => 'e' }])
        ]
      end

      it 'keeps the snapshot tail in place, ahead of the later deltas' do
        expect(history).to eq(
          [
            message('a'),
            message('b'),
            message('c', thread_ts: 'ts-2', parent_ts: 'ts-1'),
            message('d', thread_ts: 'ts-2', parent_ts: 'ts-1'),
            message('e', thread_ts: 'ts-2', parent_ts: 'ts-1')
          ]
        )
      end
    end

    context 'with a trimmed snapshot that does not restate the fold' do
      # The gateway trims ui_chat_log at compaction, so the snapshot holds only the
      # entries from that step and the summary card, not the prior history. The
      # message_id tells a new entry from one the fold already has.
      def entry(id, content = id)
        { 'message_id' => id, 'content' => content }
      end

      def stamped(id, content = id, thread_ts: 'ts-1', parent_ts: nil)
        entry(id, content).merge('thread_ts' => thread_ts, 'parent_ts' => parent_ts)
      end

      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', step_action: 'compaction', value: [entry('m1')]),
          blob(channel: 'ui_chat_log', version: '2', value: [entry('m2'), entry('m3')]),
          blob(channel: 'ui_chat_log', version: '3', value: [entry('m4'), entry('m5')]),
          blob(channel: 'ui_chat_log', version: '4', thread_ts: 'ts-2', step_action: 'compaction',
            value: [entry('m6'), entry('c1', 'summary')]),
          blob(channel: 'ui_chat_log', version: '5', thread_ts: 'ts-2', value: [entry('m7')])
        ]
      end

      it 'appends the summary card and the step entries once, ahead of the later deltas' do
        expect(history).to eq(
          [
            stamped('m1'), stamped('m2'), stamped('m3'), stamped('m4'), stamped('m5'),
            stamped('m6', thread_ts: 'ts-2', parent_ts: 'ts-1'),
            stamped('c1', 'summary', thread_ts: 'ts-2', parent_ts: 'ts-1'),
            stamped('m7', thread_ts: 'ts-2', parent_ts: 'ts-1')
          ]
        )
      end

      context 'with a restart re-seed of the trimmed log' do
        # A restart re-seeds the log since the last compaction. Every id is already
        # in the fold, so the re-seed adds nothing.
        let(:blobs) do
          super() << blob(channel: 'ui_chat_log', version: '6', thread_ts: 'ts-2', step_action: 'compaction',
            value: [entry('m6'), entry('c1', 'summary'), entry('m7')])
        end

        it 'keeps each message once' do
          expect(history.map { |entry| entry['message_id'] }).to eq(%w[m1 m2 m3 m4 m5 m6 c1 m7])
        end
      end

      context 'with a re-seed that repeats an entry under a changed id-less shape' do
        # An entry without an id compares whole against the snapshot's own fields,
        # so the stamp keys the fold added do not make it look new.
        let(:blobs) do
          [
            blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
            blob(channel: 'ui_chat_log', version: '2', step_action: 'compaction',
              value: [{ 'content' => 'a' }, entry('m2')])
          ]
        end

        it 'adds only the entry the fold has not seen' do
          expect(history).to eq([message('a'), stamped('m2')])
        end
      end
    end

    context 'with deltas from several checkpoints' do
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'ui_chat_log', version: '2', thread_ts: 'ts-2',
            value: [{ 'content' => 'b' }, { 'content' => 'c' }])
        ]
      end

      it 'stamps each message with the checkpoint that introduced it' do
        expect(history).to eq(
          [
            message('a'),
            message('b', thread_ts: 'ts-2', parent_ts: 'ts-1'),
            message('c', thread_ts: 'ts-2', parent_ts: 'ts-1')
          ]
        )
      end
    end

    context 'with a turn the user retried' do
      let(:alternatives) { { 'ts-2' => 1 } }
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a', 'message_type' => 'agent' }]),
          blob(channel: 'ui_chat_log', version: '2', thread_ts: 'ts-2',
            value: [{ 'content' => 'b', 'message_type' => 'user' }, { 'content' => 'c', 'message_type' => 'agent' }])
        ]
      end

      it 'counts alternatives on the user message anchoring the turn, and nowhere else' do
        expect(history.map { |entry| entry.values_at('content', 'alternative_count') })
          .to eq([['a', nil], ['b', 1], ['c', nil]])
      end
    end

    context 'with a turn the user never retried' do
      let(:blobs) do
        [blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a', 'message_type' => 'user' }])]
      end

      it 'reports no alternatives rather than leaving the count unset' do
        expect(history.first['alternative_count']).to eq(0)
      end
    end

    context 'with a checkpoint missing from the ancestry map' do
      let(:ancestry) { {} }
      let(:blobs) { [blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }])] }

      it 'still stamps the thread_ts, leaving the fork point unknown' do
        expect(history).to eq([message('a')])
      end
    end

    context 'with a group-0 seed snapshot' do
      # The earliest snapshot seeds the base (e.g. a resumed workflow's starting log).
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', step_action: 'compaction',
            value: [{ 'content' => 'seed' }]),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'a' }])
        ]
      end

      it 'seeds from the earliest snapshot and appends the deltas' do
        expect(history).to eq([message('seed'), message('a')])
      end
    end

    context 'with a restart re-seed snapshot after earlier deltas' do
      # A gateway restart re-seeds the full current log as a compaction. It adds
      # nothing past the earlier deltas, so history keeps each message once.
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }]),
          blob(channel: 'ui_chat_log', version: '3', step_action: 'compaction',
            value: [{ 'content' => 'a' }, { 'content' => 'b' }]),
          blob(channel: 'ui_chat_log', version: '4', value: [{ 'content' => 'c' }])
        ]
      end

      it 'drops the re-seed snapshot and keeps every delta once' do
        expect(history).to eq([message('a'), message('b'), message('c')])
      end
    end

    context 'with other channels present' do
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'context', version: '2', value: { 'goal' => 'x' }, step_action: 'compaction')
        ]
      end

      it 'folds only the requested channel' do
        expect(history).to eq([message('a')])
      end
    end

    context 'with a conversation and a compaction blob that share a version' do
      # This fold drops mid-stream compactions, so it must keep the conversation
      # delta of the colliding version, not the compaction.
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'ui_chat_log', version: '2', step_action: 'compaction',
            value: [{ 'content' => 'summary' }]),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }])
        ]
      end

      it 'keeps the conversation delta and drops the same-version compaction' do
        expect(history).to eq([message('a'), message('b')])
      end
    end

    context 'with a same-version collision whose rows are not adjacent' do
      # The v1 retry arrives after v2, so the winning row sits later in the chain. Order
      # comes from where v1 first appeared, otherwise v2 would precede v1 in the history.
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', step_action: 'compaction',
            value: [{ 'content' => 'stale' }]),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }]),
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'ui_chat_log', version: '3', value: [{ 'content' => 'c' }])
        ]
      end

      it 'places the winning row at the version first occurrence' do
        expect(history).to eq([message('a'), message('b'), message('c')])
      end
    end

    context 'with no blobs for the channel' do
      let(:blobs) { [] }

      it { is_expected.to be_nil }
    end
  end

  describe '#channel_changes' do
    context 'with a replace-semantics channel (status)' do
      subject(:changes) { described_class.new(blobs).channel_changes('status') }

      # The gateway has no delta form for a scalar, so it stamps every status write
      # 'compaction' (_serialize_channel_blobs only sets 'conversation' for list and
      # dict appends). These fixtures mirror that.
      let(:blobs) do
        [
          blob(channel: 'status', version: '1', step_action: 'compaction', value: 'running'),
          blob(channel: 'status', version: '2', step_action: 'compaction', value: 'paused'),
          blob(channel: 'status', version: '3', step_action: 'compaction', value: 'running')
        ]
      end

      it 'keeps every value the channel took, oldest first' do
        expect(changes).to eq(%w[running paused running])
      end
    end

    context 'with a scalar channel re-seeded at a new thread group' do
      subject(:changes) { described_class.new(blobs).channel_changes('status') }

      let(:blobs) do
        [
          blob(channel: 'status', version: '1', step_action: 'compaction', value: 'running'),
          # A restart re-seeds every channel as a full snapshot, unchanged value included.
          blob(channel: 'status', version: '1', step_action: 'compaction', value: 'running',
            thread_ts: 'ts-2'),
          blob(channel: 'status', version: '2', step_action: 'compaction', value: 'completed',
            thread_ts: 'ts-2')
        ]
      end

      it 'drops the re-seed and keeps the real transition' do
        expect(changes).to eq(%w[running completed])
      end
    end

    context 'with a nullable scalar channel (goal)' do
      subject(:changes) { described_class.new(blobs).channel_changes('goal') }

      let(:blobs) do
        [
          blob(channel: 'goal', version: '1', step_action: 'compaction', value: nil),
          blob(channel: 'goal', version: '2', step_action: 'compaction', value: 'ship it'),
          blob(channel: 'goal', version: '3', step_action: 'compaction', value: 'ship it')
        ]
      end

      it 'keeps the nil seed and skips the repeated value' do
        expect(changes).to eq([nil, 'ship it'])
      end
    end

    context 'with a nil-seeded dict channel (last_human_input)' do
      subject(:changes) { described_class.new(blobs).channel_changes('last_human_input') }

      # The channel starts nil, so its type only shows up from the second blob on. The
      # nil must not make the whole channel read as a scalar.
      let(:blobs) do
        [
          blob(channel: 'last_human_input', version: '1', step_action: 'compaction', value: nil),
          blob(channel: 'last_human_input', version: '2', step_action: 'compaction',
            value: { 'id' => '1', 'message' => 'go' }),
          blob(channel: 'last_human_input', version: '3', value: { 'id' => '2' })
        ]
      end

      it 'keeps the nil seed and reads the rest as a dict channel' do
        expect(changes).to eq([nil, { 'id' => '2' }])
      end
    end

    context 'with a nil-seeded list channel' do
      subject(:changes) { described_class.new(blobs).channel_changes('additional_context') }

      let(:blobs) do
        [
          blob(channel: 'additional_context', version: '1', step_action: 'compaction', value: nil),
          blob(channel: 'additional_context', version: '2', value: [{ 'c' => 'a' }]),
          blob(channel: 'additional_context', version: '3', value: [{ 'c' => 'b' }])
        ]
      end

      it 'expands the later deltas instead of nesting them' do
        expect(changes).to eq([nil, { 'c' => 'a' }, { 'c' => 'b' }])
      end
    end

    context 'with a dict channel whose step edit is written as a replacement' do
      subject(:changes) { described_class.new(blobs).channel_changes('plan') }

      # An in-place step edit is not an append, so the gateway writes the whole plan as a
      # 'compaction'. We drop it rather than re-record every step (see #collection_changes).
      let(:blobs) do
        [
          blob(channel: 'plan', version: '1', value: { 'steps' => [{ 'id' => 1, 'status' => 'pending' }] }),
          blob(channel: 'plan', version: '2', value: { 'steps' => [{ 'id' => 2, 'status' => 'pending' }] }),
          blob(channel: 'plan', version: '3', step_action: 'compaction', value: {
            'steps' => [{ 'id' => 1, 'status' => 'done' }, { 'id' => 2, 'status' => 'pending' }]
          })
        ]
      end

      it 'keeps the appended steps and drops the edit snapshot' do
        expect(changes).to eq(
          [
            { 'steps' => [{ 'id' => 1, 'status' => 'pending' }] },
            { 'steps' => [{ 'id' => 2, 'status' => 'pending' }] }
          ]
        )
      end
    end

    context 'with a list channel around a mid-chain compaction' do
      subject(:changes) { described_class.new(blobs).channel_changes('ui_chat_log') }

      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }]),
          blob(channel: 'ui_chat_log', version: '3', step_action: 'compaction',
            value: [{ 'content' => 'summary' }]),
          blob(channel: 'ui_chat_log', version: '4', value: [{ 'content' => 'c' }])
        ]
      end

      it 'expands the message deltas and keeps the compaction summary in place' do
        expect(changes).to eq(
          [{ 'content' => 'a' }, { 'content' => 'b' }, { 'content' => 'summary' }, { 'content' => 'c' }]
        )
      end
    end

    context 'with a trimmed compaction snapshot' do
      subject(:changes) { described_class.new(blobs).channel_changes('ui_chat_log') }

      def entry(id)
        { 'message_id' => id, 'content' => id }
      end

      # The gateway trims ui_chat_log at compaction, so the snapshot holds only its own
      # step's entries and the summary card. A later restart re-seed repeats them.
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [entry('m1'), entry('m2')]),
          blob(channel: 'ui_chat_log', version: '2', step_action: 'compaction', value: [entry('m3'), entry('c1')]),
          blob(channel: 'ui_chat_log', version: '3', value: [entry('m4')]),
          blob(channel: 'ui_chat_log', version: '4', step_action: 'compaction',
            value: [entry('m3'), entry('c1'), entry('m4')])
        ]
      end

      it 'keeps the snapshot entries once, in place, and ignores the re-seed' do
        expect(changes.pluck('message_id')).to eq(%w[m1 m2 m3 c1 m4])
      end
    end

    context 'with an initial compaction snapshot' do
      subject(:changes) { described_class.new(blobs).channel_changes('ui_chat_log') }

      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', step_action: 'compaction',
            value: [{ 'content' => 'seed' }]),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'a' }])
        ]
      end

      it 'seeds from the initial snapshot and keeps the later changes' do
        expect(changes).to eq([{ 'content' => 'seed' }, { 'content' => 'a' }])
      end
    end

    context 'with a list channel whose changes only the compaction snapshot records' do
      subject(:changes) { described_class.new(blobs).channel_changes('ui_chat_log') }

      # The step that triggers a compaction writes a full snapshot instead of a
      # delta, so 'b' is recorded nowhere else.
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'ui_chat_log', version: '2', step_action: 'compaction',
            value: [{ 'content' => 'a' }, { 'content' => 'b' }]),
          blob(channel: 'ui_chat_log', version: '3', value: [{ 'content' => 'c' }])
        ]
      end

      it 'keeps the snapshot tail in place, ahead of the later deltas' do
        expect(changes).to eq([{ 'content' => 'a' }, { 'content' => 'b' }, { 'content' => 'c' }])
      end
    end

    context 'with only empty-array deltas before a mid-chain compaction' do
      subject(:changes) { described_class.new(blobs).channel_changes('ui_chat_log') }

      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: []),
          blob(channel: 'ui_chat_log', version: '2', step_action: 'compaction',
            value: [{ 'content' => 'summary' }]),
          blob(channel: 'ui_chat_log', version: '3', value: [{ 'content' => 'a' }])
        ]
      end

      it 'keeps the whole snapshot, since no change was recorded before it' do
        expect(changes).to eq([{ 'content' => 'summary' }, { 'content' => 'a' }])
      end
    end

    context 'with a snapshot that replaces the list' do
      subject(:changes) { described_class.new(blobs).channel_changes('additional_context') }

      # additional_context has replace semantics, so 'a' is gone and 'x', 'y', 'z' are
      # new. Every entry the list has not held before is a change worth recording.
      let(:blobs) do
        [
          blob(channel: 'additional_context', version: '1', value: %w[a]),
          blob(channel: 'additional_context', version: '2', step_action: 'compaction',
            value: %w[x y z])
        ]
      end

      it 'records every new entry rather than splicing the snapshot by length' do
        expect(changes).to eq(%w[a x y z])
      end
    end

    context 'with a conversation and a compaction blob that share a version' do
      subject(:changes) { described_class.new(blobs).channel_changes('ui_chat_log') }

      # Prefer the conversation delta: keeping the compaction instead would drop
      # the change, since #channel_changes skips mid-stream compactions.
      let(:blobs) do
        [
          blob(channel: 'ui_chat_log', version: '1', value: [{ 'content' => 'a' }]),
          blob(channel: 'ui_chat_log', version: '2', step_action: 'compaction',
            value: [{ 'content' => 'summary' }]),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'b' }])
        ]
      end

      it 'keeps the conversation delta of the colliding version' do
        expect(changes).to eq([{ 'content' => 'a' }, { 'content' => 'b' }])
      end
    end

    context 'with no blobs for the channel' do
      subject(:changes) { described_class.new([]).channel_changes('status') }

      it { is_expected.to eq([]) }
    end
  end

  describe '#scalar_values_by_thread_ts' do
    subject(:values) { described_class.new(blobs).scalar_values_by_thread_ts('status') }

    context 'with one blob per checkpoint' do
      let(:blobs) do
        [
          blob(channel: 'status', version: '1', value: 'running', thread_ts: 'ts-1'),
          blob(channel: 'status', version: '2', value: 'input_required', thread_ts: 'ts-2'),
          blob(channel: 'ui_chat_log', version: '2', value: [{ 'content' => 'a' }], thread_ts: 'ts-2')
        ]
      end

      it 'maps each checkpoint to its own value, ignoring the other channels' do
        expect(values).to eq('ts-1' => 'running', 'ts-2' => 'input_required')
      end
    end

    context 'with a version that holds both a delta and a compaction' do
      let(:collision) do
        [
          blob(channel: 'status', version: '1', value: 'running', thread_ts: 'ts-1'),
          blob(channel: 'status', version: '1', value: 'input_required', thread_ts: 'ts-1',
            step_action: 'compaction')
        ]
      end

      let(:blobs) { collision }

      it 'takes the compaction, which carries the full value' do
        expect(values).to eq('ts-1' => 'input_required')
      end

      context 'when the compaction comes first' do
        let(:blobs) { collision.reverse }

        it 'still takes the compaction, so the read does not depend on write order' do
          expect(values).to eq('ts-1' => 'input_required')
        end
      end
    end

    context 'when a checkpoint wrote the channel more than once' do
      let(:blobs) do
        [
          blob(channel: 'status', version: '1', value: 'running', thread_ts: 'ts-1'),
          blob(channel: 'status', version: '2', value: 'input_required', thread_ts: 'ts-1')
        ]
      end

      it 'keeps the last value, since blobs arrive oldest first' do
        expect(values).to eq('ts-1' => 'input_required')
      end
    end

    context 'with no blobs for the channel' do
      let(:blobs) { [] }

      it { is_expected.to eq({}) }
    end
  end
end
