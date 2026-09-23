# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Ai::Messaging::Conversation, feature_category: :duo_agent_platform do
  # 18 chars for single-digit counts; silent at zero (Slack-style).
  let(:counting_marker) { ->(count) { "<!-- #{count} omitted -->" if count > 0 } }
  # Always speaks, so every output states completeness (notes-style).
  let(:completeness_marker) { ->(count) { count == 0 ? '<!-- full -->' : '<!-- trimmed -->' } }

  def conversation(messages, marker: counting_marker)
    described_class.new(messages: messages, marker: marker)
  end

  describe '#to_s' do
    it 'joins the messages without a marker when the marker is silent at zero' do
      expect(conversation(%w[oldest newest]).to_s).to eq("oldest\nnewest")
    end

    it 'prefixes the zero-count marker when the marker always speaks' do
      expect(conversation(%w[oldest newest], marker: completeness_marker).to_s)
        .to eq("<!-- full -->\noldest\nnewest")
    end
  end

  describe '#keep_newest_within' do
    context 'when everything fits' do
      it 'returns the plain join' do
        expect(conversation(%w[oldest middle newest]).keep_newest_within(100)).to eq("oldest\nmiddle\nnewest")
      end

      it 'fits at the exact boundary' do
        joined = "oldest\nnewest"

        expect(conversation(%w[oldest newest]).keep_newest_within(joined.length)).to eq(joined)
      end

      it 'includes the zero-count marker when the marker always speaks' do
        expect(conversation(%w[only], marker: completeness_marker).keep_newest_within(100)).to eq("<!-- full -->\nonly")
      end

      it 'counts the zero-count marker against the budget' do
        expect(conversation(%w[only], marker: completeness_marker).keep_newest_within(4)).to be_nil
      end
    end

    context 'when the budget forces dropping' do
      it 'keeps the largest fitting suffix, prefixed with a marker counting the dropped' do
        messages = [('o' * 30), ('m' * 10), ('n' * 10)]

        # Full join is 52; dropping the oldest yields 18 + 1 + 10 + 1 + 10 = 40.
        expect(conversation(messages).keep_newest_within(45)).to eq("<!-- 1 omitted -->\n#{'m' * 10}\n#{'n' * 10}")
      end

      it 'counts the marker itself against the budget' do
        # "newest" alone (6 chars) fits in 10, but not with the 18-char marker.
        expect(conversation(%w[oldest newest]).keep_newest_within(10)).to be_nil
      end

      it 'keeps the marker when only the newest message survives' do
        messages = [('o' * 30), ('m' * 30), 'tiny']

        expect(conversation(messages).keep_newest_within(30)).to eq("<!-- 2 omitted -->\ntiny")
      end
    end

    context 'when not even the newest message fits' do
      it 'returns nil' do
        expect(conversation(['x' * 50, 'y' * 50]).keep_newest_within(40)).to be_nil
      end
    end

    context 'with an empty conversation' do
      it 'returns an empty string when the marker is silent' do
        expect(conversation([]).keep_newest_within(10)).to eq('')
      end

      it 'returns a marker-only block when the marker always speaks' do
        expect(conversation([], marker: completeness_marker).keep_newest_within(100)).to eq('<!-- full -->')
      end
    end
  end

  describe '#render_within' do
    let(:messages) { [('o' * 30), ('m' * 10), ('n' * 10)] }

    it 'measures the exact render overhead with an empty render, then wraps the fitted conversation' do
      # 'PRE[' + ']' = 5 chars of overhead; budget 45 leaves 40, exactly the one-dropped suffix.
      goal, = conversation(messages).render_within(45) { |text| "PRE[#{text}]" }

      expect(goal).to eq("PRE[<!-- 1 omitted -->\n#{'m' * 10}\n#{'n' * 10}]")
    end

    it 'also returns the fitted conversation, so callers can re-wrap it' do
      _goal, fitted = conversation(messages).render_within(45) { |text| "PRE[#{text}]" }

      expect(fitted).to eq("<!-- 1 omitted -->\n#{'m' * 10}\n#{'n' * 10}")
    end

    it 'returns the wrapped goal when everything fits' do
      goal, = conversation(%w[oldest newest]).render_within(100) { |text| "PRE[#{text}]" }

      expect(goal).to eq("PRE[oldest\nnewest]")
    end

    it 'returns nil when not even the newest message fits the remaining budget' do
      expect(conversation(['x' * 50]).render_within(20) { |text| text }).to be_nil
    end

    context 'when the render is not additive and the wrapped goal overflows' do
      it 'fires on_overflow with the wrapped length and overhead, then returns nil', :aggregate_failures do
        captured = {}
        doubling = ->(text) { "PRE[#{text}#{text}]" }

        goal = conversation(messages).render_within(
          45, on_overflow: ->(length, overhead) { captured = { length: length, overhead: overhead } }, &doubling
        )

        expect(goal).to be_nil
        # The 40-char fitted suffix rendered twice inside 'PRE[' + ']' = 85.
        expect(captured[:length]).to eq(85)
        expect(captured[:overhead]).to eq(5)
      end

      it 'does not fire on_overflow when nothing fits at all' do
        fired = false

        conversation(['x' * 50]).render_within(20, on_overflow: ->(*) { fired = true }) { |text| text }

        expect(fired).to be(false)
      end
    end

    context 'when the render declines the fitted conversation' do
      it 'returns nil instead of raising' do
        expect(conversation(messages).render_within(45) { |_text| nil }).to be_nil
      end
    end
  end
end
