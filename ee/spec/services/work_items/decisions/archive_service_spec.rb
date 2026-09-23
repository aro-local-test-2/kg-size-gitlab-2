# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Decisions::ArchiveService, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }
  let_it_be(:reporter) { create(:user, reporter_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }

  let_it_be_with_reload(:decision) { create(:work_item_decision, :resolved, work_item: work_item) }

  let(:current_user) { reporter }

  subject(:response) { described_class.new(decision: decision, current_user: current_user).execute }

  before do
    stub_licensed_features(ai_workflows: true)
  end

  it 'archives the decision without touching the resolution' do
    expect { response }.to change { decision.reload.archived_at }.from(nil)
      .and not_change { decision.reload.slice(:resolved_at, :resolved_by_id, :resolution_rationale) }

    expect(response).to be_success
    expect(response.payload[:decision]).to eq(decision)
    expect(decision.state).to eq(:archived)
  end

  it 'bumps updated_at' do
    decision.update_column(:updated_at, 1.day.ago)

    expect { response }.to change { decision.reload.updated_at }
  end

  context 'when the decision is already archived' do
    let_it_be_with_reload(:decision) { create(:work_item_decision, :archived, work_item: work_item) }

    it 'returns an error' do
      expect { response }.not_to change { decision.reload.updated_at }

      expect(response).to be_error
      expect(response.errors).to include('Decision is already archived')
    end
  end

  context 'when the decision is not resolved' do
    let_it_be_with_reload(:decision) { create(:work_item_decision, work_item: work_item) }

    it 'returns an error and keeps the decision active' do
      expect { response }.not_to change { decision.reload.archived_at }.from(nil)

      expect(response).to be_error
      expect(response.errors).to include('Only resolved decisions can be archived')
    end
  end

  context 'when user cannot update the work item' do
    let(:current_user) { guest }

    it 'returns an error and does not archive the decision' do
      expect { response }.not_to change { decision.reload.archived_at }.from(nil)

      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end
  end

  context 'when ai_workflows is not licensed' do
    before do
      stub_licensed_features(ai_workflows: false)
    end

    it 'returns an error' do
      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end
  end

  context 'when the work item type does not have the widget' do
    let_it_be(:incident_work_item) { create(:work_item, :incident, project: project) }

    let(:decision) { create(:work_item_decision, :resolved, work_item: incident_work_item) }

    it 'returns an error' do
      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end
  end

  context 'when decision_log is disabled' do
    before do
      stub_feature_flags(decision_log: false)
    end

    it 'returns an error' do
      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end
  end
end
