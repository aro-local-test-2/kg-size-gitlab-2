# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ci::TestBalancing, :clean_gitlab_redis_shared_state, feature_category: :code_testing do
  let_it_be(:project) { create(:project) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }

  let(:parallel_options) { { instance: 1, parallel: { total: 3 } } }

  let(:job) do
    create(:ci_build, :running, user: developer, project: project, pipeline: pipeline,
      name: 'rspec unit 1/3', options: parallel_options)
  end

  let(:tests_params) do
    [
      { path: 'spec/models/a_spec.rb', expected_duration: 10.5 },
      { path: 'spec/models/b_spec.rb', expected_duration: 5.0 },
      { path: 'spec/models/c_spec.rb' }
    ]
  end

  before do
    stub_licensed_features(ci_parallel_test_balancing: true)
  end

  shared_examples 'a test balancing endpoint' do
    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(parallel_test_balancing: false)
      end

      it 'returns 404' do
        perform_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the project does not have the required license' do
      before do
        stub_licensed_features(ci_parallel_test_balancing: false)
      end

      it 'returns 404' do
        perform_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when authenticated with a personal access token' do
      subject(:perform_request) { post api(path, developer), params: request_params.except(:job_token) }

      it 'returns 404' do
        perform_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the job is not a parallel job' do
      let(:parallel_options) { {} }

      it 'returns 422' do
        perform_request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to eq('Job is not a parallel job')
      end
    end

    context 'when the pipeline is older than the retention period' do
      it 'returns 422' do
        travel_to(pipeline.created_at + ::Ci::TestBalancing::Assignment::RETENTION_PERIOD + 1.day) do
          perform_request
        end

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to include('within')
      end
    end
  end

  describe 'POST /job/test_balancing/initialize' do
    let(:path) { '/job/test_balancing/initialize' }
    let(:request_params) { { job_token: job.token, test_splits: tests_params } }

    subject(:perform_request) { post api(path), params: request_params }

    it_behaves_like 'a test balancing endpoint'

    context 'on the first run of the node' do
      it 'creates test splits, seeds the queue, and returns a first claimed batch', :aggregate_failures do
        perform_request

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['mode']).to eq('seed')
        expect(json_response['test_splits']).to be_present

        expect(::Ci::TestBalancing::JobGroup.find_by_name('rspec unit')).to be_present
        expect(::Ci::TestBalancing::TestSplit.pluck(:path)).to match_array(tests_params.map { |f| f[:path] })
      end

      it 'persists a durable assignment per claimed test' do
        perform_request

        claimed_count = ::Ci::TestBalancing::Assignment.where(node_index: 1).count
        expect(claimed_count).to eq(json_response['test_splits'].size)
      end
    end

    context 'when another node already seeded the same tests' do
      before do
        other_job = create(:ci_build, :running, user: developer, project: project, pipeline: pipeline,
          name: 'rspec unit 2/3', options: { instance: 2, parallel: { total: 3 } })

        post api(path), params: { job_token: other_job.token, test_splits: tests_params }
      end

      it 'does not duplicate test split records' do
        expect { perform_request }.not_to change { ::Ci::TestBalancing::TestSplit.count }
      end
    end

    context 'when the node already has claimed tests' do
      before do
        perform_request
      end

      it 'replays the previously claimed set without touching the queue', :aggregate_failures do
        first_tests = json_response['test_splits']

        retried_job = create(:ci_build, :running, user: developer, project: project, pipeline: pipeline,
          name: 'rspec unit 1/3', options: parallel_options)

        expect do
          post api(path), params: { job_token: retried_job.token, test_splits: tests_params }
        end.not_to change { ::Ci::TestBalancing::Assignment.where(node_index: 1).count }

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['mode']).to eq('retry')
        expect(json_response['test_splits']).to match_array(first_tests)
      end
    end

    context 'when the test splits list exceeds the per-request limit' do
      let(:request_params) do
        splits = Array.new(described_class::MAX_TEST_SPLITS + 1) { |i| { path: "spec/#{i}_spec.rb" } }
        { job_token: job.token, test_splits: splits }
      end

      it 'returns 400' do
        perform_request

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when seeding would exceed the per-job-group limit' do
      before do
        stub_const("::Ci::TestBalancing::MAX_TEST_SPLITS_PER_JOB_GROUP", 1)
      end

      it 'returns 422', :aggregate_failures do
        perform_request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to include('exceeds the limit')
      end
    end
  end

  describe 'POST /job/test_balancing/request' do
    let(:path) { '/job/test_balancing/request' }
    let(:request_params) { { job_token: job.token } }

    subject(:perform_request) { post api(path), params: request_params }

    it_behaves_like 'a test balancing endpoint'

    context 'when the pool has pending tests' do
      let(:big_tests) { Array.new(6) { |i| { path: "spec/big/#{i}_spec.rb", expected_duration: 500.0 } } }

      before do
        ::Ci::TestBalancing::InitializeService.new(job)
          .execute(big_tests)
      end

      it 'claims pending tests for the node', :aggregate_failures do
        perform_request

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['test_splits']).to be_present

        claimed_count = ::Ci::TestBalancing::Assignment.where(node_index: 1).count
        expect(claimed_count).to eq(json_response['test_splits'].size)
      end
    end

    context 'when the queue is drained' do
      it 'returns an empty array', :aggregate_failures do
        perform_request

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['test_splits']).to eq([])
      end
    end
  end
end
