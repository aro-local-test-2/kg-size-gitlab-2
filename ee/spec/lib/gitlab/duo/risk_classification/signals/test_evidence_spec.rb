# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::TestEvidence, feature_category: :duo_code_review do
  let(:merge_request) { build(:merge_request) }
  let(:paths) { [] }

  subject(:signal) { described_class.new(merge_request) }

  before do
    allow(merge_request).to receive(:modified_paths).and_return(paths)
  end

  it_behaves_like 'a signal with dimensions', 'Test evidence', {
    untested: 'Source changes without a matching test'
  }

  describe '#available?' do
    context 'when paths are known' do
      let(:paths) { ['app/models/a.rb'] }

      it { is_expected.to be_available }
    end

    context 'when nothing changed' do
      it { is_expected.not_to be_available }
    end
  end

  describe '#extract' do
    context 'when source changes ship without tests' do
      let(:paths) { %w[app/models/a.rb app/models/b.rb] }

      it 'reports maximum risk' do
        expect(signal.extract[:untested]).to eq(1.0)
      end
    end

    context 'when every source change is matched by a test change' do
      let(:paths) { %w[app/models/a.rb ee/spec/models/a_spec.rb] }

      it 'reports no risk' do
        expect(signal.extract[:untested]).to eq(0.0)
      end
    end

    context 'when only some source changes are matched' do
      let(:paths) { %w[app/models/a.rb app/models/b.rb spec/models/a_spec.rb] }

      it 'reports partial risk' do
        expect(signal.extract[:untested]).to eq(0.5)
      end
    end

    context 'when there are more test changes than source changes' do
      let(:paths) { %w[app/models/a.rb spec/models/a_spec.rb spec/models/b_spec.rb] }

      it 'does not report negative risk' do
        expect(signal.extract[:untested]).to eq(0.0)
      end
    end

    context 'when the change touches no source at all' do
      let(:paths) { %w[doc/index.md CHANGELOG.md config/database.yml] }

      it 'reports no risk rather than penalising a docs change' do
        expect(signal.extract[:untested]).to eq(0.0)
      end
    end

    describe 'test path recognition' do
      where(:path) do
        [
          ['spec/models/a_spec.rb'],
          ['ee/spec/models/a_spec.rb'],
          ['test/models/a_test.rb'],
          ['qa/qa/specs/a.rb'],
          ['app/assets/javascripts/__tests__/a.js'],
          ['app/assets/javascripts/a.spec.js'],
          ['app/assets/javascripts/a.test.ts'],
          ['workhorse/internal/a_test.go'],
          ['scripts/test_a.py']
        ]
      end

      with_them do
        let(:paths) { ['app/models/a.rb', path] }

        it 'counts as a test change' do
          expect(signal.extract[:untested]).to eq(0.0)
        end
      end
    end
  end
end
