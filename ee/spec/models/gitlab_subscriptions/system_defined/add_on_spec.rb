# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::SystemDefined::AddOn, feature_category: :subscription_management do
  describe 'parity with the ActiveRecord model' do
    it 'has one item per AR enum entry with id == enum value' do
      expect(described_class.all.to_h { |a| [a.name, a.id] })
        .to eq(GitlabSubscriptions::AddOn.names)
    end

    it 'carries the AR descriptions verbatim' do
      expect(described_class.all.to_h { |a| [a.name.to_sym, a.description] })
        .to eq(GitlabSubscriptions::AddOn.descriptions)
    end

    it 'mirrors the AR constants' do
      expect(described_class::DUO_ADD_ONS).to eq(GitlabSubscriptions::AddOn::DUO_ADD_ONS)
      expect(described_class::SEAT_ASSIGNABLE_DUO_ADD_ONS)
        .to eq(GitlabSubscriptions::AddOn::SEAT_ASSIGNABLE_DUO_ADD_ONS)
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:description) }
  end

  describe '.names' do
    it 'returns the string-name-to-id hash the AR enum returned' do
      expect(described_class.names).to eq(GitlabSubscriptions::AddOn.names)
    end

    it 'accepts symbol keys like the AR enum' do
      expect(described_class.names[:duo_enterprise]).to eq(3)
    end
  end

  describe '.uids_for_names' do
    it 'maps names to ids, skipping unknown names, accepting symbols and strings' do
      expect(described_class.uids_for_names([:code_suggestions, 'duo_enterprise', :nope])).to match_array([1, 3])
    end

    it 'wraps a single name' do
      expect(described_class.uids_for_names(:duo_core)).to eq([5])
    end
  end

  describe '.names_for_uids' do
    it 'maps ids to names, skipping unknown ids' do
      expect(described_class.names_for_uids([1, 3, 99])).to eq(%w[code_suggestions duo_enterprise])
    end
  end

  describe '#seat_assignable?' do
    it 'is true only for code_suggestions and duo_enterprise' do
      expect(described_class.all.select(&:seat_assignable?).map(&:name))
        .to match_array(%w[code_suggestions duo_enterprise])
    end
  end

  describe 'name predicates' do
    it 'defines a predicate per item name' do
      item = described_class.find_by!(name: 'duo_enterprise')

      expect(item.duo_enterprise?).to be(true)
      expect(item.code_suggestions?).to be(false)
    end
  end
end
