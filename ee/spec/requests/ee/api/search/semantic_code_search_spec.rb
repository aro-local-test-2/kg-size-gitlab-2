# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::API::Search::SemanticCodeSearch, :api, :clean_gitlab_redis_rate_limiting, feature_category: :global_search do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :private) }

  let_it_be(:api_token) do
    create(:personal_access_token, scopes: %w[api], user: user)
  end

  let_it_be(:ai_workflows_token) do
    create(:oauth_access_token, scopes: [:ai_workflows], resource_owner: user)
  end

  let_it_be(:read_user_token) do
    create(:personal_access_token, scopes: %w[read_user], user: user)
  end

  # Not a member of the private project: resolving user_project 404s before the route
  # block runs. Distinct from :guest_user below, which does reach `authorize!`.
  let_it_be(:non_member) { create(:user) }
  let_it_be(:non_member_token) { create(:personal_access_token, scopes: %w[api], user: non_member) }

  # A member whose role has no read_code (see config/authz/roles/guest.yml), so
  # user_project resolves and `authorize! :read_code` is the thing that rejects.
  let_it_be(:guest_user) { create(:user) }
  let_it_be(:guest_token) { create(:personal_access_token, scopes: %w[api], user: guest_user) }

  let(:path) { "/projects/#{project.id}/search/semantic" }
  let(:params) { { q: 'authentication logic' } }
  let(:hits) do
    [
      {
        'path' => 'app/models/user.rb',
        'content' => 'def authenticate',
        'blob_id' => 'abc123',
        'start_line' => 42,
        'file_url' => "https://gitlab.com/#{project.full_path}/-/blob/main/app/models/user.rb",
        'score' => 0.95
      },
      {
        'path' => 'app/models/user.rb',
        'content' => 'def verify_token',
        'blob_id' => 'abc123',
        'start_line' => 80,
        'file_url' => "https://gitlab.com/#{project.full_path}/-/blob/main/app/models/user.rb",
        'score' => 0.88
      },
      {
        'path' => 'lib/auth/middleware.rb',
        'content' => 'def call(env)',
        'blob_id' => 'def456',
        'start_line' => 10,
        'file_url' => "https://gitlab.com/#{project.full_path}/-/blob/main/lib/auth/middleware.rb",
        'score' => 0.72
      }
    ]
  end

  let(:success_result) { ::Ai::ActiveContext::Queries::Result.success(hits) }
  let(:error_result) do
    ::Ai::ActiveContext::Queries::Result.no_embeddings_error(
      error_detail: 'initial indexing is still ongoing, try again in a few minutes'
    )
  end

  before_all do
    project.add_developer(user)
    project.add_guest(guest_user)
  end

  before do
    allow(::Ai::ActiveContext::Queries::Code).to receive(:available?).and_return(true)
    allow_next_instance_of(::Ai::ActiveContext::Queries::Code) do |instance|
      allow(instance).to receive(:filter).and_return(success_result)
    end
  end

  describe 'GET /projects/:id/search/semantic' do
    subject(:get_api) { get api(path, personal_access_token: api_token), params: params }

    context 'when user is not authenticated' do
      it 'returns 401' do
        get api(path), params: params

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when token lacks sufficient scope' do
      it 'returns 403 for read_user scope' do
        get api(path, personal_access_token: read_user_token), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'allows ai_workflows scope' do
        get api(path, oauth_access_token: ai_workflows_token), params: params

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when project does not exist' do
      it 'returns 404' do
        get api("/projects/#{non_existing_record_id}/search/semantic",
          personal_access_token: api_token), params: params

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when user lacks read_code permission' do
      it 'returns 404 for non-member on private project' do
        get api(path, personal_access_token: non_member_token), params: params

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns 403 for a member whose role lacks read_code' do
        get api(path, personal_access_token: guest_token), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when semantic search service is unavailable' do
      before do
        allow(::Ai::ActiveContext::Queries::Code).to receive(:new)
          .and_raise(::Ai::ActiveContext::Queries::Code::NotAvailable)
      end

      it 'returns 404' do
        get_api

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'records no SLI observation for the 404' do
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_error_rate)
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_apdex)

        get_api

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when project has no embeddings' do
      before do
        allow_next_instance_of(::Ai::ActiveContext::Queries::Code) do |instance|
          allow(instance).to receive(:filter).and_return(error_result)
        end
      end

      it 'returns 422 with error message' do
        get_api

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to include('has no embeddings')
      end

      it 'does not trigger ad-hoc indexing' do
        expect(::Ai::ActiveContext::Code::AdHocIndexingWorker).not_to receive(:perform_async)

        get_api
      end

      it 'records no SLI observation for the 422' do
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_error_rate)
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_apdex)

        get_api

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
      end
    end

    context 'when a file is excluded from Duo context' do
      before do
        exclusion_result = ServiceResponse.success(
          payload: [
            { path: 'app/models/user.rb', excluded: true },
            { path: 'lib/auth/middleware.rb', excluded: false }
          ]
        )
        allow_next_instance_of(::Ai::FileExclusionService) do |svc|
          allow(svc).to receive(:execute).and_return(exclusion_result)
        end
      end

      it 'omits excluded files from results' do
        get_api

        expect(response).to have_gitlab_http_status(:ok)
        paths = json_response['results'].pluck('path')
        expect(paths).to contain_exactly('lib/auth/middleware.rb')
        expect(paths).not_to include('app/models/user.rb')
      end
    end

    context 'with valid request' do
      it_behaves_like 'authorizing granular token permissions', :read_code do
        let(:boundary_object) { project }
        let(:request) { get api(path, personal_access_token: pat), params: params }
      end

      it 'returns 200 with grouped results and confidence' do
        get_api

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('confidence', 'results')
        expect(json_response['results']).to be_an(Array)
      end

      it 'groups multiple hits from the same file' do
        get_api

        user_rb = json_response['results'].find { |r| r['path'] == 'app/models/user.rb' }
        expect(user_rb).to include('path' => 'app/models/user.rb', 'blob_id' => 'abc123')
        expect(user_rb['snippet_ranges'].length).to eq(2)
        expect(user_rb['snippet_ranges'].first).to include(
          'start_line' => 42,
          'content' => 'def authenticate',
          'score' => 0.95
        )
      end

      it 'returns separate grouped result for each distinct file' do
        get_api

        paths = json_response['results'].pluck('path')
        expect(paths).to contain_exactly('app/models/user.rb', 'lib/auth/middleware.rb')
      end

      it 'includes a confidence level' do
        get_api

        expect(json_response['confidence']).to be_in(%w[high medium low unknown])
      end

      it 'tracks internal event with confidence, transport and result count' do
        expect { get_api }.to trigger_internal_events('search_code_with_semantic_search').with(
          user: user, project: project, namespace: project.root_namespace,
          category: 'InternalEventTracking',
          additional_properties: { label: 'medium', property: 'rest_api', value: 2 }
        )
      end

      context 'when the request arrives over MCP' do
        # Mcp::Tools::Base::ApiTool#execute runs this Grape route directly via
        # route.exec, so the MCP transport reaches the same code path. The token scope is
        # what distinguishes it.
        let_it_be(:mcp_token) { create(:oauth_access_token, resource_owner: user, scopes: [:mcp]) }

        it 'labels the event with the mcp transport' do
          expect { get api(path, oauth_access_token: mcp_token), params: params }
            .to trigger_internal_events('search_code_with_semantic_search').with(
              user: user, project: project, namespace: project.root_namespace,
              category: 'InternalEventTracking',
              additional_properties: { label: 'medium', property: 'mcp', value: 2 }
            )
        end
      end

      it 'does not emit the event when result filtering fails' do
        allow_next_instance_of(::Ai::FileExclusionService) do |svc|
          allow(svc).to receive(:execute).and_raise(StandardError, 'boom')
        end

        expect { get_api }.not_to trigger_internal_events('search_code_with_semantic_search')

        expect(response).to have_gitlab_http_status(:internal_server_error)
      end

      it 'records an SLI error when result filtering fails' do
        allow_next_instance_of(::Ai::FileExclusionService) do |svc|
          allow(svc).to receive(:execute).and_raise(StandardError, 'boom')
        end

        expect(Gitlab::Metrics::GlobalSearchSlis).to receive(:record_error_rate)
          .with(hash_including(error: true))

        get_api
      end

      it 'records an SLI error when the event emission raises' do
        allow(Gitlab::InternalEvents).to receive(:track_event)
          .with('search_code_with_semantic_search', anything)
          .and_raise(StandardError, 'boom')

        expect(Gitlab::Metrics::GlobalSearchSlis).to receive(:record_error_rate)
          .with(hash_including(error: true))

        get_api

        expect(response).to have_gitlab_http_status(:internal_server_error)
      end

      # Grape's `present` calls Entity.represent inside the route block, but the actual
      # JSON encoding runs in the formatter middleware after the block (and its ensure)
      # has returned. So a failure while building the representation is catchable here;
      # one while encoding it is not, by any rescue in this endpoint.
      # The apdex call sits above `present`, so this request is deliberately counted as a
      # fast apdex success *and* an error-rate failure at once - the same shape
      # lib/api/search.rb has. Asserted so the ordering is pinned rather than incidental.
      it 'records an SLI error when building the response representation raises' do
        allow(::API::Entities::Ai::SemanticCode::Response).to receive(:represent)
          .and_raise(StandardError, 'boom')

        expect(Gitlab::Metrics::GlobalSearchSlis).to receive(:record_apdex)
          .with(hash_including(search_type: 'semantic'))
        expect(Gitlab::Metrics::GlobalSearchSlis).to receive(:record_error_rate)
          .with(hash_including(error: true))

        get_api

        expect(response).to have_gitlab_http_status(:internal_server_error)
      end

      it 'records a Global Search apdex SLI' do
        expect(Gitlab::Metrics::GlobalSearchSlis).to receive(:record_apdex).with(
          elapsed: an_instance_of(Float),
          search_type: 'semantic',
          search_level: 'project',
          search_scope: 'blobs'
        )

        get_api
      end

      it 'records a Global Search error rate SLI without an error' do
        expect(Gitlab::Metrics::GlobalSearchSlis).to receive(:record_error_rate).with(
          error: false,
          search_type: 'semantic',
          search_level: 'project',
          search_scope: 'blobs'
        )

        get_api
      end

      it 'includes file_url in each result' do
        get_api

        result = json_response['results'].first
        expect(result).to have_key('file_url')
        expect(result['file_url']).to be_a(String)
      end

      it 'passes q parameter to the service as search_term' do
        expect_next_instance_of(::Ai::ActiveContext::Queries::Code,
          search_term: 'authentication logic', user: user) do |instance|
          expect(instance).to receive(:filter).with(
            hash_including(
              project_or_id: project,
              path: nil,
              knn_count: 64,
              limit: 20,
              exclude_fields: %w[id source type embeddings_v1 reindexing],
              extract_source_segments: true,
              build_file_url: true
            )
          ).and_return(success_result)
        end

        get_api
      end
    end

    context 'with optional parameters' do
      let(:params) { { q: 'auth', directory_path: 'app/models', knn: 5, limit: 3 } }

      it 'forwards optional params to the service' do
        expect_next_instance_of(::Ai::ActiveContext::Queries::Code,
          search_term: 'auth', user: user) do |instance|
          expect(instance).to receive(:filter).with(
            hash_including(path: 'app/models', knn_count: 5, limit: 3)
          ).and_return(success_result)
        end

        get_api

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'with invalid parameters' do
      it 'returns 400 when q is missing' do
        get api(path, personal_access_token: api_token), params: {}

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'returns 400 when q is blank' do
        get api(path, personal_access_token: api_token), params: { q: '' }

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'returns 400 when knn is out of range' do
        get api(path, personal_access_token: api_token), params: params.merge(knn: 0)

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'returns 400 when limit exceeds maximum' do
        get api(path, personal_access_token: api_token), params: params.merge(limit: 101)

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'returns 400 when directory_path starts with /' do
        get api(path, personal_access_token: api_token), params: params.merge(directory_path: '/app/models')

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'returns 400 when directory_path contains .. segments' do
        get api(path, personal_access_token: api_token), params: params.merge(directory_path: 'app/../etc')

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when the request is rejected before a search runs' do
      it 'records no SLI observation for a param validation failure' do
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_error_rate)
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_apdex)

        get api(path, personal_access_token: api_token), params: params.merge(directory_path: '/app')

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'records no SLI observation when the project is not found' do
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_error_rate)
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_apdex)

        get api(path, personal_access_token: non_member_token), params: params

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'records no SLI observation when authorization fails' do
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_error_rate)
        expect(Gitlab::Metrics::GlobalSearchSlis).not_to receive(:record_apdex)

        get api(path, personal_access_token: guest_token), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when the AI Gateway rate limit is exhausted' do
      before do
        allow_next_instance_of(::Ai::ActiveContext::Queries::Code) do |instance|
          allow(instance).to receive(:filter).and_raise(
            ::Gitlab::Llm::Concerns::ExponentialBackoff::RateLimitError,
            'Maximum number of retries (3) exceeded.'
          )
        end
      end

      it 'returns 429' do
        get_api

        expect(response).to have_gitlab_http_status(:too_many_requests)
      end

      it 'sets a Retry-After header' do
        get_api

        expect(response.headers['Retry-After']).to eq(60)
      end
    end

    context 'when the search backend times out' do
      where(:error_class) do
        [::Elastic::TimeoutError, ::Faraday::TimeoutError, ::Net::ReadTimeout]
      end

      with_them do
        before do
          allow_next_instance_of(::Ai::ActiveContext::Queries::Code) do |instance|
            allow(instance).to receive(:filter).and_raise(error_class, 'Timeout was reached')
          end
        end

        it 'returns 503' do
          get_api

          expect(response).to have_gitlab_http_status(:service_unavailable)
        end

        it 'sets a Retry-After header' do
          get_api

          expect(response.headers['Retry-After']).to eq('30')
        end
      end
    end

    context 'when an unrelated error occurs' do
      before do
        allow_next_instance_of(::Ai::ActiveContext::Queries::Code) do |instance|
          allow(instance).to receive(:filter).and_raise(StandardError, 'boom')
        end
      end

      it 'is not rescued by the new handlers and still returns 500' do
        get_api

        expect(response).to have_gitlab_http_status(:internal_server_error)
      end
    end

    context 'when rate limited', :freeze_time do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:semantic_search_rate_limit, scope: [user])
          .and_return(true)
      end

      it 'returns 429' do
        get_api

        expect(response).to have_gitlab_http_status(:too_many_requests)
      end
    end
  end
end
