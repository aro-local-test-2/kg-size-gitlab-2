# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::AdapterRegistry, feature_category: :duo_agent_platform do
  describe '.[]' do
    it 'resolves the slack adapter' do
      expect(described_class['slack']).to eq(Ai::Messaging::Adapters::Slack)
    end

    it 'resolves the gitlab_duo_note adapter' do
      expect(described_class['gitlab_duo_note']).to eq(Ai::Messaging::Adapters::GitlabDuoNote)
    end

    it 'resolves the webhook adapter' do
      expect(described_class['webhook']).to eq(Ai::Messaging::Adapters::Webhook)
    end

    it 'returns nil for an unknown adapter key' do
      expect(described_class['unknown']).to be_nil
    end
  end
end
