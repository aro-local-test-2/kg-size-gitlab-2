# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::RolloutGuard, feature_category: :duo_code_review do
  let(:merge_request) { build(:merge_request) }
  let(:paths) { [] }

  subject(:signal) { described_class.new(merge_request) }

  before do
    allow(merge_request).to receive(:modified_paths).and_return(paths)
  end

  it_behaves_like 'a signal with dimensions', 'Feature flag rollout', {
    feature_flag: 'Change ships behind a feature flag'
  }

  it 'reports a mitigation rather than a risk' do
    expect(described_class).to be_mitigation
  end

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
    context 'when no flag definition is touched' do
      let(:paths) { %w[app/models/a.rb config/routes.rb] }

      it 'reports no mitigation' do
        expect(signal.extract[:feature_flag]).to eq(0.0)
      end
    end

    where(:path) do
      [
        ['config/feature_flags/wip/duo_mr_risk_classification.yml'],
        ['ee/config/feature_flags/development/some_flag.yml'],
        ['jh/config/feature_flags/ops/some_flag.yaml']
      ]
    end

    with_them do
      let(:paths) { ['app/models/a.rb', path] }

      it 'reports the change as guarded' do
        expect(signal.extract[:feature_flag]).to eq(1.0)
      end
    end
  end
end
