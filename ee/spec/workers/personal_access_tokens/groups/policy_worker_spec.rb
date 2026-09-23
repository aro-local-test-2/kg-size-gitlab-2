# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PersonalAccessTokens::Groups::PolicyWorker, feature_category: :system_access do
  subject(:worker) { described_class.new }

  let_it_be(:group) { create(:group_with_managed_accounts) }

  describe '#perform' do
    it 'is no-op' do
      expect(worker.perform(group.id)).to be_nil
    end
  end
end
