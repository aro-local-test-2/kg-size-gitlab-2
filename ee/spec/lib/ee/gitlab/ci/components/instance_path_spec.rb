# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Components::InstancePath, feature_category: :pipeline_composition do
  let_it_be(:user) { create(:user) }

  let(:path) { described_class.new(address: address) }
  let(:server_fqdn) { 'acme.com' }

  before do
    allow(Gitlab.config.gitlab).to receive(:server_fqdn).and_return(server_fqdn)
  end

  describe '#fetch_content_for_policy_access' do
    let_it_be(:project, freeze: false) do
      create(:project, :custom_repo, files: { 'templates/test.yml' => 'test: content' })
    end

    let(:project_path) { project.full_path }
    let(:address) { "acme.com/#{project_path}/test@master" }

    it 'returns component content without access checks' do
      result = path.fetch_content_for_policy_access

      expect(result.content).to eq('test: content')
    end

    context 'when project is nil' do
      let(:address) { "acme.com/nonexistent/project/test@master" }

      it 'returns nil' do
        expect(path.fetch_content_for_policy_access).to be_nil
      end
    end
  end
end
