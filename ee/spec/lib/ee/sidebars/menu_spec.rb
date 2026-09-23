# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidebars::Menu, feature_category: :navigation do
  let(:context) { Sidebars::Context.new(current_user: nil, container: nil) }
  let(:menu) { described_class.new(context) }

  describe '#tier_for' do
    subject(:tier) { menu.send(:tier_for, feature) }

    context 'with a premium feature' do
      let(:feature) { :epics }

      it { is_expected.to eq(:premium) }
    end

    context 'with an ultimate feature' do
      let(:feature) { :security_dashboard }

      it { is_expected.to eq(:ultimate) }
    end

    context 'with a starter feature' do
      let(:feature) do
        (GitlabSubscriptions::Features::STARTER_FEATURES - GitlabSubscriptions::Features::GLOBAL_FEATURES).first
      end

      it 'maps the retired starter plan to premium' do
        expect(tier).to eq(:premium)
      end
    end

    context 'with a feature that is not licensed' do
      let(:feature) { :does_not_exist }

      it { is_expected.to be_nil }
    end
  end
end
