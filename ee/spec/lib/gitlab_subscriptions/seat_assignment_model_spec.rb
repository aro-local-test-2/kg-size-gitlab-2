# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::SeatAssignmentModel, feature_category: :seat_cost_management do
  describe '.enabled?' do
    let_it_be_with_reload(:group) { create(:group, :seat_assignment_model_enabled) }
    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:project) { create(:project, group: subgroup) }

    let(:source) { group }

    subject(:enabled) { described_class.enabled?(source) }

    context 'when on SaaS', :saas do
      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(seat_assignment_model: false)
        end

        it { is_expected.to be(false) }
      end

      it { is_expected.to be(true) }

      context 'with a subgroup source' do
        let(:source) { subgroup }

        it { is_expected.to be(true) }
      end

      context 'with a project source' do
        let(:source) { project }

        it { is_expected.to be(true) }
      end

      context 'with a project in a personal namespace' do
        let_it_be(:personal_project) { create(:project, :in_user_namespace) }

        let(:source) { personal_project }

        before do
          personal_project.root_ancestor.create_namespace_settings!(seat_assignment_model_enabled: true)
        end

        it { is_expected.to be(false) }
      end

      context 'with a nil source' do
        let(:source) { nil }

        it { is_expected.to be(false) }
      end

      context 'without namespace settings' do
        before do
          source.namespace_settings.destroy!
          source.reload
        end

        it { is_expected.to be(false) }
      end

      context 'when the seat assignment model setting is disabled' do
        before do
          group.namespace_settings.update!(seat_assignment_model_enabled: false)
        end

        it { is_expected.to be(false) }
      end
    end

    context 'when on self-managed' do
      it { is_expected.to be(false) }
    end
  end
end
