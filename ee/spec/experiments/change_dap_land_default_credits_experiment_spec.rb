# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ChangeDapLandDefaultCreditsExperiment, :experiment, feature_category: :activation do
  let(:experiment_name) { :change_dap_land_default_credits }
  let(:exp) { experiment(experiment_name) }

  it 'resolves the experiment name to this class' do
    expect(described_class).to eq(Gitlab::Experiment.constantize(experiment_name))
  end

  it 'declares namespace as its context key' do
    expect(described_class.context_keys).to eq(%i[namespace])
  end

  context 'with control experience' do
    before do
      stub_experiments(experiment_name => :control)
    end

    it 'returns nil' do
      expect(exp.run).to be_nil
    end
  end

  context 'with candidate experience' do
    before do
      stub_experiments(experiment_name => :candidate)
    end

    it 'returns the candidate quantity' do
      expect(exp.run).to eq(ChangeDapLandDefaultCreditsExperiment::CANDIDATE_QUANTITY)
    end
  end
end
