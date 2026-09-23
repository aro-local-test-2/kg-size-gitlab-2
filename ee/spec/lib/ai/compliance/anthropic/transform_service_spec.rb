# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Ai::Compliance::Anthropic::TransformService, feature_category: :compliance_management do
  let(:anthropic_user_id) { 'user_01ZYXWVU' }
  let(:message_id) { 'clsm_01J4KpLmNoPqRsTuVwXyZaBc' }
  let(:created_at) { '2026-07-09T14:02:11Z' }

  subject(:service) { described_class.new(anthropic_user_id: anthropic_user_id) }

  def message(role:, content:, provenance: nil, id: message_id, created_at: self.created_at)
    { 'id' => id, 'role' => role, 'created_at' => created_at, 'provenance' => provenance, 'content' => content }
  end

  describe '#execute' do
    context 'with a user text block' do
      let(:input) { message(role: 'user', content: [{ 'type' => 'text', 'text' => 'Fix the failing test' }]) }

      it 'maps to ai_claude_user_input_received', :aggregate_failures do
        events = service.execute(input)

        expect(events.size).to eq(1)
        expect(events.first).to include(
          event_name: 'ai_claude_user_input_received',
          created_at: Time.iso8601(created_at)
        )
        expect(events.first[:details]).to include(
          'anthropic_user_id' => anthropic_user_id,
          'text' => 'Fix the failing test',
          'text_truncated' => false,
          'text_original_bytesize' => 'Fix the failing test'.bytesize
        )
      end
    end

    context 'with an assistant text block' do
      let(:input) { message(role: 'assistant', content: [{ 'type' => 'text', 'text' => "I'll read the file." }]) }

      it 'maps to ai_claude_response_received' do
        expect(service.execute(input).first[:event_name]).to eq('ai_claude_response_received')
      end
    end

    context 'with a tool_use block' do
      let(:block) do
        { 'type' => 'tool_use', 'id' => 'toolu_01AbCdEfGhIjKlMnOpQrSt', 'name' => 'Read',
          'input' => '{"file_path":"tests/auth_test.py"}' }
      end

      let(:input) { message(role: 'assistant', content: [block]) }

      it 'maps to ai_claude_tool_invoked with parsed input', :aggregate_failures do
        details = service.execute(input).first[:details]

        expect(details).to include(
          'anthropic_user_id' => anthropic_user_id,
          'tool_use_id' => 'toolu_01AbCdEfGhIjKlMnOpQrSt',
          'name' => 'Read',
          'input_parsed' => true
        )
        expect(details['input']).to eq(
          'file_path' => { 'value' => 'tests/auth_test.py', 'truncated' => false, 'original_bytesize' => 18 }
        )
      end

      it 'never truncates the tool name, however long' do
        block['name'] = 'x' * 5_000

        expect(service.execute(input).first[:details]['name']).to eq('x' * 5_000)
      end

      it 'never truncates a parsed input key, however long, but does truncate its value' do
        long_key = 'k' * 5_000
        long_value = 'v' * 5_000
        block['input'] = { long_key => long_value }.to_json

        input_details = service.execute(input).first[:details]['input']

        expect(input_details.keys).to eq([long_key])
        expect(input_details[long_key]['value'].bytesize)
          .to eq(described_class::TOOL_USE_INPUT_VALUE_MAX_BYTES)
        expect(input_details[long_key]['truncated']).to be(true)
        expect(input_details[long_key]['original_bytesize']).to eq(5_000)
      end

      it 'truncates an oversize input value at TOOL_USE_INPUT_VALUE_MAX_BYTES bytes, without splitting a character' do
        # 3-byte UTF-8 character; byteslice(max_bytes) here would cut mid-character.
        multibyte_char = "☃"
        oversize_value = multibyte_char * 1_000
        block['input'] = { 'content' => oversize_value }.to_json

        value_details = service.execute(input).first[:details]['input']['content']

        expect(value_details['truncated']).to be(true)
        expect(value_details['original_bytesize']).to eq(oversize_value.bytesize)
        expect(value_details['value'].bytesize).to be <= described_class::TOOL_USE_INPUT_VALUE_MAX_BYTES
        expect(value_details['value'].valid_encoding?).to be(true)
      end

      it 'leaves an input value at or under the byte cap untouched' do
        block['input'] = { 'file_path' => 'short.rb' }.to_json

        value_details = service.execute(input).first[:details]['input']['file_path']

        expect(value_details).to eq('value' => 'short.rb', 'truncated' => false, 'original_bytesize' => 8)
      end

      it 'caps a nested input value at TOOL_USE_INPUT_VALUE_MAX_BYTES, measured as JSON', :aggregate_failures do
        edits = [{ 'old_string' => 'a' * 3_000, 'new_string' => 'b' * 3_000 }]
        block['input'] = { 'file_path' => 'a.rb', 'edits' => edits }.to_json

        value_details = service.execute(input).first[:details]['input']['edits']

        expect(value_details['truncated']).to be(true)
        expect(value_details['original_bytesize']).to eq(Gitlab::Json.dump(edits).bytesize)
        expect(value_details['value']).to be_a(String)
        expect(value_details['value'].bytesize).to eq(described_class::TOOL_USE_INPUT_VALUE_MAX_BYTES)
      end

      it 'does not split a multibyte character when cutting a nested input value' do
        block['input'] = { 'edits' => ["☃" * 1_000] }.to_json

        value_details = service.execute(input).first[:details]['input']['edits']

        expect(value_details['value'].valid_encoding?).to be(true)
      end

      it 'keeps the parsed shape of a nested input value that fits the cap', :aggregate_failures do
        todos = [{ 'content' => 'Fix the test', 'status' => 'pending' }]
        block['input'] = { 'todos' => todos }.to_json

        value_details = service.execute(input).first[:details]['input']['todos']

        expect(value_details['value']).to eq(todos)
        expect(value_details['truncated']).to be(false)
        expect(value_details['original_bytesize']).to eq(Gitlab::Json.dump(todos).bytesize)
      end

      context 'when the input was already cut upstream and no longer parses as JSON' do
        before do
          block['input'] = '{"file_path":"tests/very/long/path/that/got/cut/off/mid-str'
        end

        it 'stores a flagged raw prefix instead of parsed values, keeping name separate', :aggregate_failures do
          details = service.execute(input).first[:details]

          expect(details['name']).to eq('Read')
          expect(details['input_parsed']).to be(false)
          expect(details['input_raw']).to eq(block['input'])
          expect(details['input_raw_truncated']).to be(false)
          expect(details['input_raw_original_bytesize']).to eq(block['input'].bytesize)
          expect(details).not_to have_key('input')
        end
      end
    end

    context 'with a successful tool_result block' do
      let(:block) do
        { 'type' => 'tool_result', 'tool_use_id' => 'toolu_01AbCdEfGhIjKlMnOpQrSt', 'name' => 'Read',
          'is_error' => false, 'content' => [{ 'type' => 'text', 'text' => 'file contents' }] }
      end

      let(:input) { message(role: 'user', content: [block]) }

      it 'maps to ai_claude_tool_response_received and truncates content at the success limit', :aggregate_failures do
        details = service.execute(input).first[:details]

        expect(service.execute(input).first[:event_name]).to eq('ai_claude_tool_response_received')
        expect(details).to include('tool_use_id' => 'toolu_01AbCdEfGhIjKlMnOpQrSt', 'name' => 'Read')
        expect(details['content']).to eq(
          [{ 'text' => 'file contents', 'text_truncated' => false, 'text_original_bytesize' => 13 }]
        )
      end

      it 'truncates oversize success content at TOOL_RESULT_SUCCESS_MAX_BYTES' do
        block['content'] = [{ 'type' => 'text', 'text' => 'a' * 2_000 }]

        entry = service.execute(input).first[:details]['content'].first

        expect(entry['text'].bytesize).to eq(described_class::TOOL_RESULT_SUCCESS_MAX_BYTES)
        expect(entry['text_truncated']).to be(true)
        expect(entry['text_original_bytesize']).to eq(2_000)
      end
    end

    context 'with a failed tool_result block' do
      let(:block) do
        { 'type' => 'tool_result', 'tool_use_id' => 'toolu_01AbCdEfGhIjKlMnOpQrSt', 'name' => 'Read',
          'is_error' => true, 'content' => [{ 'type' => 'text', 'text' => 'a' * 3_000 }] }
      end

      let(:input) { message(role: 'user', content: [block]) }

      it 'maps to ai_claude_tool_execution_failed and truncates content at the error limit', :aggregate_failures do
        result = service.execute(input).first
        entry = result[:details]['content'].first

        expect(result[:event_name]).to eq('ai_claude_tool_execution_failed')
        expect(entry['text'].bytesize).to eq(described_class::TOOL_RESULT_ERROR_MAX_BYTES)
        expect(entry['text_truncated']).to be(true)
      end
    end

    context 'with a message whose content is unavailable' do
      let(:input) do
        message(
          role: 'user', content: [],
          provenance: { 'type' => 'content_unavailable', 'reason' => 'retention_elapsed' }
        )
      end

      it 'maps to ai_claude_content_unavailable and records the reason', :aggregate_failures do
        events = service.execute(input)

        expect(events.size).to eq(1)
        expect(events.first[:event_name]).to eq('ai_claude_content_unavailable')
        expect(events.first[:details]).to eq(
          'anthropic_user_id' => anthropic_user_id,
          'reason' => 'retention_elapsed'
        )
      end
    end

    context 'with a message carrying an unrecognized content block type' do
      let(:input) { message(role: 'user', content: [{ 'type' => 'image' }]) }

      it 'produces no event' do
        expect(service.execute(input)).to eq([])
      end
    end

    context 'with several content blocks in one message' do
      let(:input) do
        message(
          role: 'assistant',
          content: [
            { 'type' => 'text', 'text' => "I'll read the file first." },
            { 'type' => 'tool_use', 'id' => 'toolu_01AbCdEfGhIjKlMnOpQrSt', 'name' => 'Read',
              'input' => '{"file_path":"tests/auth_test.py"}' }
          ]
        )
      end

      it 'returns one event per block, in order' do
        expect(service.execute(input).map { |e| e[:event_name] }).to eq(
          %w[ai_claude_response_received ai_claude_tool_invoked]
        )
      end
    end

    describe 'created_at' do
      it 'is always the upstream message timestamp, never ingestion time' do
        travel_to(Time.utc(2030, 1, 1)) do
          input = message(role: 'user', content: [{ 'type' => 'text', 'text' => 'hi' }], created_at: created_at)

          expect(service.execute(input).first[:created_at]).to eq(Time.iso8601(created_at))
        end
      end
    end

    describe 'cloud_event_id' do
      it 'is a valid UUIDv5' do
        input = message(role: 'user', content: [{ 'type' => 'text', 'text' => 'hi' }])

        expect(service.execute(input).first[:cloud_event_id]).to match(Gitlab::UUID::UUID_V5_PATTERN)
      end

      it 'is deterministic for a tool_use block, keyed on the tool_use id alone' do
        block = { 'type' => 'tool_use', 'id' => 'toolu_stable', 'name' => 'Read', 'input' => '{}' }
        first_input = message(role: 'assistant', content: [block], id: 'clsm_first')
        second_input = message(role: 'assistant', content: [block], id: 'clsm_second')

        first_id = service.execute(first_input).first[:cloud_event_id]
        second_id = service.execute(second_input).first[:cloud_event_id]

        expect(first_id).to eq(second_id)
      end

      it 'differs by position for two blocks of the same type in the same message' do
        input = message(
          role: 'user',
          content: [
            { 'type' => 'tool_result', 'tool_use_id' => 'toolu_a', 'name' => 'Read', 'is_error' => false,
              'content' => [] },
            { 'type' => 'tool_result', 'tool_use_id' => 'toolu_b', 'name' => 'Read', 'is_error' => false,
              'content' => [] }
          ]
        )

        ids = service.execute(input).map { |e| e[:cloud_event_id] }

        expect(ids.uniq.size).to eq(2)
      end

      it 'does not collide between a tool_result and the tool_use block sharing its tool_use_id' do
        tool_use_id = 'toolu_01AbCdEfGhIjKlMnOpQrSt'
        tool_use_message = message(
          role: 'assistant',
          content: [{ 'type' => 'tool_use', 'id' => tool_use_id, 'name' => 'Read', 'input' => '{}' }],
          id: 'clsm_assistant'
        )
        tool_result_message = message(
          role: 'user',
          content: [{ 'type' => 'tool_result', 'tool_use_id' => tool_use_id, 'name' => 'Read',
                      'is_error' => false, 'content' => [] }],
          id: 'clsm_user'
        )

        tool_use_event_id = service.execute(tool_use_message).first[:cloud_event_id]
        tool_result_event_id = service.execute(tool_result_message).first[:cloud_event_id]

        expect(tool_use_event_id).not_to eq(tool_result_event_id)
      end
    end
  end
end
