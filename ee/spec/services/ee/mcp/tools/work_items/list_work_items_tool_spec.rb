# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::ListWorkItemsTool, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }

  let(:tool) { described_class.new(current_user: user, params: arguments, version: '0.1.0') }

  before_all do
    project.add_developer(user)
  end

  describe '#build_variables' do
    context 'with EE filters' do
      let(:arguments) do
        {
          project_id: project.id.to_s,
          health_status_filter: 'onTrack',
          status: { name: 'In progress' }
        }
      end

      it 'maps them onto their GraphQL variables' do
        expect(tool.build_variables).to include(
          healthStatusFilter: 'onTrack',
          status: { name: 'In progress' }
        )
      end
    end
  end
end
