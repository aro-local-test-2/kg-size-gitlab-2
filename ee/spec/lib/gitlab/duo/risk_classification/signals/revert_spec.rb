# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::Revert, feature_category: :duo_code_review do
  let(:attributes) { {} }
  let(:merge_request) { build(:merge_request, **attributes) }

  subject(:signal) { described_class.new(merge_request) }

  it_behaves_like 'a signal with dimensions', 'Revert', {
    reverts_prior_change: 'Reverts a previously merged change'
  }

  it 'reports a mitigation rather than a risk' do
    expect(described_class).to be_mitigation
  end

  describe '#available?' do
    it { is_expected.to be_available }
  end

  describe '#extract' do
    context 'with an ordinary merge request' do
      let(:attributes) do
        { source_branch: 'add-widget', title: 'Add a widget', description: 'Reverting nothing here' }
      end

      it 'reports no mitigation' do
        expect(signal.extract[:reverts_prior_change]).to eq(0.0)
      end
    end

    context 'when the branch follows the revert convention' do
      let(:attributes) { { source_branch: 'revert-a1b2c3d4', title: 'Undo the widget' } }

      it 'reports a revert' do
        expect(signal.extract[:reverts_prior_change]).to eq(1.0)
      end
    end

    context 'when the title follows the revert convention' do
      let(:attributes) { { source_branch: 'undo-widget', title: 'Revert "Add a widget"' } }

      it 'reports a revert' do
        expect(signal.extract[:reverts_prior_change]).to eq(1.0)
      end
    end

    context 'when the description names the reverted commit' do
      let(:attributes) do
        { source_branch: 'undo-widget', title: 'Undo', description: 'This reverts commit a1b2c3d4e5f6' }
      end

      it 'reports a revert' do
        expect(signal.extract[:reverts_prior_change]).to eq(1.0)
      end
    end

    context 'when the description names the reverted merge request' do
      let(:attributes) do
        { source_branch: 'undo-widget', title: 'Undo', description: 'This reverts merge request !123' }
      end

      it 'reports a revert' do
        expect(signal.extract[:reverts_prior_change]).to eq(1.0)
      end
    end

    context 'when the description has no reference' do
      let(:attributes) { { source_branch: 'undo-widget', title: 'Undo', description: nil } }

      it 'reports no mitigation' do
        expect(signal.extract[:reverts_prior_change]).to eq(0.0)
      end
    end
  end
end
