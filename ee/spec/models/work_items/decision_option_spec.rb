# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::DecisionOption, feature_category: :team_planning do
  describe 'associations' do
    it 'belongs to a decision' do
      is_expected.to belong_to(:decision)
        .class_name('WorkItems::Decision')
        .with_foreign_key(:work_item_decision_id)
        .inverse_of(:options)
    end

    it { is_expected.to belong_to(:namespace) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:decision) }
    it { is_expected.to validate_presence_of(:namespace) }
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_length_of(:content).is_at_most(described_class::CONTENT_LENGTH_MAX) }
    it { is_expected.to validate_length_of(:description).is_at_most(described_class::DESCRIPTION_LENGTH_MAX) }

    describe 'recommended and selected flags' do
      let_it_be(:decision) { create(:work_item_decision) }

      it 'allows multiple recommended options on the same decision' do
        create(:work_item_decision_option, :recommended, decision: decision)

        expect(create(:work_item_decision_option, :recommended, decision: decision)).to be_persisted
      end

      it 'allows multiple selected options on the same decision' do
        create(:work_item_decision_option, :selected, decision: decision)

        expect(create(:work_item_decision_option, :selected, decision: decision)).to be_persisted
      end
    end

    describe 'options count limit' do
      let_it_be(:decision) { create(:work_item_decision) }

      before do
        stub_const('WorkItems::Decision::MAX_OPTIONS_PER_DECISION', 2)
        create_list(:work_item_decision_option, 2, decision: decision)
      end

      it 'rejects a new option once the decision is at the limit' do
        option = build(:work_item_decision_option, decision: decision)

        expect(option).not_to be_valid
        expect(option.errors[:base]).to include(a_string_matching(/cannot have more than 2 options/))
      end

      it 'still allows updating an existing option of a full decision' do
        option = decision.options.order(:id).first

        expect(option.update(selected: true)).to be(true)
      end
    end
  end

  describe '#set_namespace' do
    it 'copies the namespace from the decision' do
      decision = create(:work_item_decision)
      option = build(:work_item_decision_option, decision: decision, namespace: nil)

      expect(option).to be_valid
      expect(option.namespace).to eq(decision.namespace)
    end
  end

  describe 'factory' do
    it 'is valid' do
      expect(build(:work_item_decision_option)).to be_valid
    end

    it 'is valid with traits' do
      expect(build(:work_item_decision_option, :recommended, :selected)).to be_valid
    end
  end
end
