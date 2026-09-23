# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Duo::CodeReview::FindingsParser, feature_category: :duo_code_review do
  let(:finding) do
    {
      file: 'app/models/user.rb',
      new_line: 42,
      old_line: 40,
      target_code: '    user.save',
      message: "**[Major] error-handling**\n\nUnchecked return value.",
      suggestion: '    user.save!',
      severity: 'major'
    }
  end

  let(:findings) { [finding] }
  let(:summary) { 'I focused on the persistence layer.' }
  let(:review_output) { { findings: findings, summary: summary }.to_json }

  subject(:parser) { described_class.new(review_output) }

  describe '.structured?' do
    it 'is true for a JSON object, tolerating leading whitespace' do
      expect(described_class.structured?(review_output)).to be(true)
      expect(described_class.structured?("  \n{}")).to be(true)
    end

    it 'is false for XML review output, blank strings and nil' do
      expect(described_class.structured?('<review></review>')).to be(false)
      expect(described_class.structured?('')).to be(false)
      expect(described_class.structured?(nil)).to be(false)
    end
  end

  describe '#comments' do
    subject(:comments) { parser.comments }

    it 'builds one Comment per finding with the same attributes the XML parser emits' do
      expect(comments.size).to eq(1)

      comment = comments.first
      expect(comment).to be_a(Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser::Comment)
      expect(comment.file).to eq('app/models/user.rb')
      expect(comment.new_line).to eq(42)
      expect(comment.old_line).to eq(40)
      expect(comment.from).to eq('    user.save')
    end

    it 'keeps the message as the content and carries the suggestion separately' do
      expect(comments.first.content).to eq(finding[:message])
      expect(comments.first.suggestion).to eq('    user.save!')
    end

    it 'exposes severity' do
      expect(comments.first.severity).to eq('major')
    end

    context 'when the finding carries an end_line' do
      let(:finding) { super().merge(end_line: 45) }

      it 'exposes it as an integer' do
        expect(comments.first.end_line).to eq(45)
      end
    end

    context 'when the optional fields are absent' do
      let(:finding) { super().except(:suggestion, :severity) }

      it 'leaves them nil' do
        comment = comments.first

        expect(comment.suggestion).to be_nil
        expect(comment.end_line).to be_nil
        expect(comment.severity).to be_nil
      end
    end

    context 'when the suggestion is identical to the target code' do
      let(:finding) { super().merge(suggestion: finding_target_code) }
      let(:finding_target_code) { '    user.save' }

      it 'drops the suggestion' do
        expect(comments.first.suggestion).to be_nil
      end
    end

    context 'when old_line is absent' do
      let(:finding) { super().except(:old_line) }

      it 'leaves old_line nil' do
        expect(comments.first.old_line).to be_nil
        expect(comments.first.new_line).to eq(42)
      end
    end

    context 'when a finding is missing required fields' do
      let(:findings) { [finding, { file: 'x.rb', message: 'no line' }, 'not a hash'] }

      it 'drops the invalid findings and keeps the rest' do
        expect(comments.map(&:file)).to eq(['app/models/user.rb'])
      end
    end

    context 'when findings is empty' do
      let(:findings) { [] }

      it { is_expected.to be_empty }
    end
  end

  describe '#comments_summary and #no_issues_summary' do
    it 'exposes the summary as comments_summary when there are comments' do
      expect(parser.comments_summary).to eq(summary)
      expect(parser.no_issues_summary).to be_nil
    end

    context 'when there are no comments' do
      let(:findings) { [] }

      it 'exposes the summary as no_issues_summary' do
        expect(parser.no_issues_summary).to eq(summary)
        expect(parser.comments_summary).to be_nil
      end
    end

    context 'when the summary is blank' do
      let(:summary) { '  ' }

      it 'returns nil for both' do
        expect(parser.comments_summary).to be_nil
        expect(parser.no_issues_summary).to be_nil
      end
    end

    context 'when a re-review sends previous findings' do
      let(:previous_findings) { "- **Still outstanding:** `app/models/user.rb`: Unchecked return value." }
      let(:review_output) { { findings: findings, summary: summary, previous_findings: previous_findings }.to_json }

      it 'keeps the summary as comments_summary while there are comments' do
        expect(parser.comments_summary).to eq(summary)
        expect(parser.no_issues_summary).to be_nil
      end

      context 'when there are no comments' do
        let(:findings) { [] }

        it 'exposes the previous findings as comments_summary instead of a clean summary' do
          expect(parser.comments_summary).to eq(previous_findings)
          expect(parser.no_issues_summary).to be_nil
        end
      end
    end
  end

  describe 'malformed input' do
    context 'when the review output is not valid JSON' do
      let(:review_output) { '{"findings": [' }

      it 'raises a parser error' do
        expect { parser.comments }.to raise_error(described_class::Error, /not valid JSON/)
      end
    end

    context 'when the review output is a JSON array' do
      let(:review_output) { '[]' }

      it 'raises a parser error' do
        expect { parser.comments }.to raise_error(described_class::Error, /must be a JSON object/)
      end
    end

    context 'when findings is missing' do
      let(:review_output) { { summary: summary }.to_json }

      it 'raises a parser error' do
        expect { parser.comments }.to raise_error(described_class::Error, /findings array/)
      end
    end
  end
end
