# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Decisions::CreateService, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }
  let_it_be(:reporter) { create(:user, reporter_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  # refind: get_widget memoizes on the instance, so license/flag contexts
  # need a fresh work item rather than a shared memoized one
  let_it_be_with_refind(:work_item) { create(:work_item, project: project) }

  let(:current_user) { reporter }
  let(:params) do
    {
      title: 'Which storage backend should we use?',
      options: [{ content: 'Use PostgreSQL', recommended: true }, { content: 'Use Redis' }]
    }
  end

  subject(:response) do
    described_class.new(work_item: work_item, current_user: current_user, params: params).execute
  end

  before do
    stub_licensed_features(ai_workflows: true)
  end

  it 'creates the decision with its options' do
    expect { response }.to change { work_item.decisions.count }.by(1)

    expect(response).to be_success

    decision = response.payload[:decision]
    expect(decision).to have_attributes(
      title: 'Which storage backend should we use?',
      author: current_user,
      namespace: work_item.namespace
    )
    expect(decision.options.map(&:content)).to contain_exactly('Use PostgreSQL', 'Use Redis')
  end

  context 'with a source link' do
    let(:params) { { title: 'Question', source_link: 'https://example.com/thread' } }

    it 'persists the source link' do
      expect(response).to be_success
      expect(response.payload[:decision].source_link).to eq('https://example.com/thread')
    end
  end

  context 'when more options than the limit are given' do
    let(:params) do
      {
        title: 'Question',
        options: Array.new(WorkItems::Decision::MAX_OPTIONS_PER_DECISION + 1) { |i| { content: "Option #{i}" } }
      }
    end

    it 'returns an error without creating anything' do
      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors.to_sentence).to match(/cannot have more than/)
    end
  end

  context 'with resolution params' do
    let(:params) do
      {
        title: 'Which storage backend should we use?',
        resolution: { decision: 'Use PostgreSQL for the storage backend', rationale: 'Settled in the design sync' }
      }
    end

    it 'creates the decision resolved by the current user, recording the decision as the selected option' do
      expect { response }.to change { WorkItems::DecisionOption.count }.by(1)

      expect(response).to be_success

      decision = response.payload[:decision]
      expect(decision).to have_attributes(
        title: 'Which storage backend should we use?',
        resolved_by: current_user,
        resolution_rationale: 'Settled in the design sync'
      )
      expect(decision.resolved_at).to eq(decision.created_at)
      expect(decision.options.map { |option| [option.content, option.selected] })
        .to contain_exactly(['Use PostgreSQL for the storage backend', true])
    end

    context 'with blank optional inputs' do
      let(:params) do
        { title: '', source_link: '', resolution: { decision: 'Use PostgreSQL' } }
      end

      it 'normalizes blanks to nil' do
        expect(response).to be_success
        expect(response.payload[:decision]).to have_attributes(title: nil, source_link: nil)
      end
    end

    context 'without a title' do
      let(:params) do
        { resolution: { decision: 'Use PostgreSQL for the storage backend' } }
      end

      it 'creates the decision with a nil title' do
        expect(response).to be_success
        expect(response.payload[:decision].title).to be_nil
      end
    end

    context 'when the decision content is missing' do
      let(:params) do
        { title: 'Question', resolution: { rationale: 'Settled' } }
      end

      it 'returns an error without creating anything' do
        expect { response }.not_to change { WorkItems::Decision.count }

        expect(response).to be_error
        expect(response.errors.to_sentence).to match(/Content can't be blank/)
      end
    end

    context 'when resolved_by_id names another user with access' do
      let_it_be(:resolver_user) { create(:user, reporter_of: project) }

      let(:params) do
        { title: 'Question', resolution: { decision: 'Go with Redis', resolved_by_id: resolver_user.id } }
      end

      it 'records that user as the resolver' do
        expect(response).to be_success
        expect(response.payload[:decision].resolved_by).to eq(resolver_user)
      end
    end

    context 'when resolved_by_id names a user without access' do
      let_it_be(:outsider) { create(:user) }

      let(:params) do
        { title: 'Question', resolution: { decision: 'Go with Redis', resolved_by_id: outsider.id } }
      end

      it 'returns an error without creating anything' do
        expect { response }.not_to change { WorkItems::Decision.count }

        expect(response).to be_error
        expect(response.errors).to include('Resolver must have access to the work item')
      end
    end

    context 'when resolved_by_id does not exist' do
      let(:params) do
        { title: 'Question', resolution: { decision: 'Go with Redis', resolved_by_id: non_existing_record_id } }
      end

      it 'returns an error without creating anything' do
        expect { response }.not_to change { WorkItems::Decision.count }

        expect(response).to be_error
        expect(response.errors).to include('Resolver must have access to the work item')
      end
    end

    context 'when options are also given' do
      let(:params) do
        {
          title: 'Question',
          resolution: { decision: 'Go with Redis', rationale: 'Settled' },
          options: [{ content: 'Use PostgreSQL' }]
        }
      end

      it 'returns an error without creating anything' do
        expect { response }.not_to change { WorkItems::Decision.count }

        expect(response).to be_error
        expect(response.errors).to include('Options are not supported when creating a resolved decision')
      end
    end
  end

  context 'when an open decision has no title' do
    let(:params) { { options: [{ content: 'Use PostgreSQL' }] } }

    it 'returns an error without creating anything' do
      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors.to_sentence).to match(/Title can't be blank/)
    end
  end

  context 'when an option is invalid' do
    let(:params) { { title: 'Question', options: [{ content: '' }] } }

    it 'returns an error and rolls back the decision' do
      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors.to_sentence).to match(/Content can't be blank/)
    end
  end

  context 'when user cannot update the work item' do
    let(:current_user) { guest }

    it 'returns an error' do
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

    let(:work_item) { incident_work_item }

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
