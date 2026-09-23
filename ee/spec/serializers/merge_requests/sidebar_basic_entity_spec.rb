# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::SidebarBasicEntity, feature_category: :code_review_workflow do
  let(:user) { build_stubbed(:user) }
  let(:project) { build_stubbed(:project, :repository) }
  let(:merge_request) { build_stubbed(:merge_request, source_project: project) }

  let(:serializer) { MergeRequestSerializer.new(current_user: user, project: project) }

  subject(:entity) { serializer.represent(merge_request, serializer: 'sidebar') }

  describe 'ai_suggested_reviewers_available' do
    using RSpec::Parameterized::TableSyntax

    where(available: [true, false])

    with_them do
      before do
        allow(merge_request.target_project)
          .to receive(:recommend_reviewers_dap_available?).and_return(available)
      end

      it { expect(entity[:ai_suggested_reviewers_available]).to be(available) }
    end
  end
end
