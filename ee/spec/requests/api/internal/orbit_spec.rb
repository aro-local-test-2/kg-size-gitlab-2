# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Internal::Orbit, feature_category: :knowledge_graph do
  include_context 'workhorse headers'

  let(:jwt_secret) { SecureRandom.random_bytes(Gitlab::JwtAuthenticatable::SECRET_LENGTH) }

  let(:jwt_claims) do
    {
      'sub' => 'gkg-indexer:code',
      'iss' => Analytics::KnowledgeGraph::JwtAuth::ISSUER,
      'aud' => Analytics::KnowledgeGraph::JwtAuth::AUDIENCE,
      'exp' => 1.hour.from_now.to_i
    }
  end

  let(:kg_jwt_header) do
    token = JWT.encode(jwt_claims, jwt_secret, 'HS256')

    { API::Internal::Orbit::API_HEADER => token }
  end

  let(:jwt_auth_headers) { kg_jwt_header.merge(workhorse_headers) }

  before do
    allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:secret).and_return(jwt_secret)
  end

  shared_examples 'authorization' do
    context 'when not authenticated' do
      it 'returns 401' do
        send_request(project_id: project.id,
          headers: { API::Internal::Orbit::API_HEADER => '' }.merge(workhorse_headers))

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(json_response['message']).to eq('Knowledge Graph JWT authentication invalid')
      end
    end

    context 'when token is missing' do
      it 'returns 401' do
        send_request(project_id: project.id, headers: workhorse_headers)

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(json_response['message']).to eq('Knowledge Graph JWT authentication invalid')
      end
    end

    context 'when Workhorse header is missing', :verify_workhorse_jwt do
      it 'returns 403' do
        send_request(project_id: project.id, headers: kg_jwt_header)

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when the Workhorse token has an invalid signature', :verify_workhorse_jwt do
      it 'returns 403 even with a valid Orbit token' do
        token = JWT.encode(
          { 'iss' => 'gitlab-workhorse', 'iat' => Time.now.to_i }, SecureRandom.random_bytes(32), 'HS256'
        )

        send_request(project_id: project.id,
          headers: jwt_auth_headers.merge(Gitlab::Workhorse::INTERNAL_API_REQUEST_HEADER => token))

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    [
      { 'exp' => 0 },
      { 'iss' => 'another-service' },
      { 'aud' => 'another-service' },
      { 'sub' => 'user:1' }
    ].each do |invalid_claims|
      it "rejects a signed token with invalid claims: #{invalid_claims.inspect}" do
        token = JWT.encode(jwt_claims.merge(invalid_claims), jwt_secret, 'HS256')

        send_request(project_id: project.id,
          headers: { API::Internal::Orbit::API_HEADER => token }.merge(workhorse_headers))

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    it 'rejects a token signed with a different secret' do
      token = JWT.encode(jwt_claims, SecureRandom.random_bytes(Gitlab::JwtAuthenticatable::SECRET_LENGTH), 'HS256')

      send_request(project_id: project.id,
        headers: { API::Internal::Orbit::API_HEADER => token }.merge(workhorse_headers))

      expect(response).to have_gitlab_http_status(:unauthorized)
    end
  end

  shared_examples 'feature flag check' do
    context 'when feature flag is disabled' do
      before do
        stub_feature_flags(knowledge_graph_infra: false)
      end

      it 'returns 404' do
        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  shared_examples 'project not found' do
    context 'when project does not exist' do
      it 'returns 404' do
        send_request(project_id: non_existing_record_id)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  shared_examples 'repository pagination bounds' do
    [-1, 0].each do |per_page|
      it "rejects a nonpositive page size of #{per_page}" do
        send_request(project_id: project.id, params: { per_page: per_page })

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    it 'uses the default page size when per_page is null' do
      send_request(project_id: project.id)
      default_page = json_response

      send_request(project_id: project.id, params: { per_page: nil })

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq(default_page)
    end

    it 'bounds oversized page sizes before sending them to Gitaly' do
      send_request(project_id: project.id, params: { per_page: 2**64 })

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.size).to be <= Gitlab::PaginationDelegate::MAX_PER_PAGE
    end
  end

  shared_examples 'invalid repository page token' do
    it 'rejects a malformed continuation token' do
      send_request(project_id: project.id, params: { page_token: 'not-a-cursor' })

      expect(response).to have_gitlab_http_status(:bad_request)
    end
  end

  def read_keyset_pages(params:)
    send_request(project_id: project.id, params: params.merge(pagination: 'keyset', per_page: 5))
    expect(response.headers['Link']).to include('rel="next"')

    entries = []
    visited_pages = []
    loop do
      expect(response).to have_gitlab_http_status(:ok)
      entries.concat(json_response)
      next_page = response.headers['Link'].to_s[/<([^>]+)>; rel="next"/, 1]
      break unless next_page

      expect(visited_pages).not_to include(next_page)
      visited_pages << next_page
      get next_page, headers: jwt_auth_headers
    end

    entries
  end

  describe 'GET /internal/orbit/project/:project_id/info' do
    let_it_be(:project) { create(:project, :repository) }

    def send_request(project_id:, headers: jwt_auth_headers)
      get api("/internal/orbit/project/#{project_id}/info"),
        headers: headers
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'

    context 'when project exists' do
      it 'returns the project id, default branch, and default branch head' do
        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq(
          'project_id' => project.id,
          'default_branch' => project.default_branch_or_main,
          'default_branch_head_sha' => project.repository.commit.sha
        )
      end

      it 'accepts a URL-encoded project path' do
        send_request(project_id: CGI.escape(project.full_path))

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['project_id']).to eq(project.id)
      end

      context 'when a tag shares the default branch name' do
        let_it_be(:project) { create(:project, :repository) }
        let_it_be(:branch_head_sha) { project.repository.commit.sha }

        before_all do
          project.repository.add_tag(project.first_owner, project.default_branch, "#{branch_head_sha}~1")
        end

        it 'returns the branch head, not the tag target' do
          send_request(project_id: project.id)

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['default_branch_head_sha']).to eq(branch_head_sha)
        end
      end

      context 'when the project has no repository' do
        let_it_be(:project) { create(:project) }

        it 'returns the project with a null branch head' do
          send_request(project_id: project.id)

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq(
            'project_id' => project.id,
            'default_branch' => project.default_branch_or_main,
            'default_branch_head_sha' => nil
          )
        end
      end
    end
  end

  describe 'GET /internal/orbit/project/:project_id/repository/branches' do
    let_it_be(:project) { create(:project, :repository) }

    def send_request(project_id:, params: {}, headers: jwt_auth_headers)
      get api("/internal/orbit/project/#{project_id}/repository/branches"),
        params: params,
        headers: headers
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'
    include_examples 'repository pagination bounds'
    include_examples 'invalid repository page token'

    context 'when project exists' do
      it 'returns branches with their commits' do
        send_request(project_id: project.id, params: { per_page: 3 })

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.size).to eq(3)
        expect(json_response).to all(satisfy { |branch| branch.keys.to_set == %w[commit name].to_set })
        expect(json_response).to all(satisfy { |branch| branch['commit']['id'].present? })
      end

      it 'avoids N+1 database queries' do
        send_request(project_id: project.id, params: { per_page: 2 })

        control = ActiveRecord::QueryRecorder.new do
          send_request(project_id: project.id, params: { per_page: 2 })
        end

        expect do
          send_request(project_id: project.id, params: { per_page: 5 })
        end.not_to exceed_query_limit(control)
      end

      it 'does not increase Gitaly requests with the page size' do
        send_request(project_id: project.id, params: { per_page: 2 })
        control = Gitlab::GitalyClient.get_request_count

        send_request(project_id: project.id, params: { per_page: 5 })

        expect(Gitlab::GitalyClient.get_request_count).to be <= control
      end

      it 'paginates every branch exactly once in name order' do
        branches = read_keyset_pages(params: { sort: 'name_asc' })

        expect(branches.pluck('name')).to eq(project.repository.branch_names.sort)
      end

      it 'preserves continuation links when the requested page exceeds the server limit' do
        stub_const('Gitlab::PaginationDelegate::MAX_PER_PAGE', 3)

        send_request(project_id: project.id, params: { per_page: 4 })

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.size).to eq(3)
        expect(response.headers['Link']).to include('rel="next"')
      end

      it 'sorts branches by the given field' do
        send_request(project_id: project.id, params: { sort: 'name_asc', per_page: 5 })

        expect(response).to have_gitlab_http_status(:ok)
        names = json_response.pluck('name')
        expect(names).to eq(names.sort)
      end

      it 'rejects an unknown sort value' do
        send_request(project_id: project.id, params: { sort: 'bogus' })

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'rejects legacy pagination' do
        send_request(project_id: project.id, params: { pagination: 'legacy' })

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      context 'when the project has no repository' do
        let_it_be(:empty_project) { create(:project) }

        it 'returns an empty collection' do
          send_request(project_id: empty_project.id)

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq([])
        end
      end
    end
  end

  describe 'GET /internal/orbit/project/:project_id/repository/tree' do
    let_it_be(:project) { create(:project, :repository) }

    def send_request(project_id:, params: {}, headers: jwt_auth_headers)
      get api("/internal/orbit/project/#{project_id}/repository/tree"),
        params: params,
        headers: headers
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'
    include_examples 'repository pagination bounds'
    include_examples 'invalid repository page token'

    context 'when project exists' do
      it 'returns an exact recursive tree for a ref' do
        send_request(
          project_id: project.id,
          params: { ref: project.repository.commit.sha, recursive: true, pagination: 'none' }
        )

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include(
          include('path' => SeedRepo::Commit::FILES.first, 'type' => 'blob', 'id' => be_present)
        )
      end

      it 'paginates every entry of a pinned recursive tree exactly once' do
        params = { ref: project.repository.commit.sha, recursive: true }
        send_request(project_id: project.id, params: params.merge(pagination: 'none'))
        expect(response).to have_gitlab_http_status(:ok)
        expected_entries = json_response

        expect(read_keyset_pages(params: params)).to match_array(expected_entries)
      end

      it 'includes the last commit for each tree entry' do
        send_request(project_id: project.id, params: { with_last_commit: true })

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to all(include('last_commit' => include('id' => be_present)))
      end

      it 'returns 404 when the ref does not exist' do
        send_request(project_id: project.id, params: { ref: 'does-not-exist' })

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns 404 when the path does not exist' do
        send_request(project_id: project.id, params: { path: 'does-not-exist' })

        expect(response).to have_gitlab_http_status(:not_found)
        expect(json_response['message']).to include('invalid revision or path')
      end

      it 'rejects unpaginated non-recursive trees' do
        send_request(project_id: project.id, params: { recursive: false, pagination: 'none' })

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'rejects recursive trees with last commit details' do
        send_request(project_id: project.id, params: { recursive: true, with_last_commit: true })

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end
  end

  describe 'GET /internal/orbit/project/:project_id/repository/archive' do
    let_it_be(:project) { create(:project, :repository) }

    def send_request(project_id:, ref: nil, include_lfs_blobs: nil, headers: jwt_auth_headers)
      params = {}
      params[:ref] = ref if ref
      params[:include_lfs_blobs] = include_lfs_blobs unless include_lfs_blobs.nil?

      get api("/internal/orbit/project/#{project_id}/repository/archive"),
        params: params,
        headers: headers
    end

    def sent_archive_params
      encoded_params = response.headers[Gitlab::Workhorse::SEND_DATA_HEADER].delete_prefix('git-archive:')

      Gitlab::Json.safe_parse(Base64.urlsafe_decode64(encoded_params))
    end

    def sent_archive_request
      Gitaly::GetArchiveRequest.decode(Base64.decode64(sent_archive_params['GetArchiveRequest']))
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'

    context 'when project exists' do
      it 'sends a git archive response for the default branch' do
        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]).to start_with('git-archive:')
      end

      it 'forwards the client_name derived from the JWT subject' do
        send_request(project_id: project.id)

        encoded_params = response.headers[Gitlab::Workhorse::SEND_DATA_HEADER].delete_prefix('git-archive:')
        decoded = Gitlab::Json.safe_parse(Base64.urlsafe_decode64(encoded_params))

        expect(decoded.dig('GitalyServer', 'call_metadata', 'client_name')).to eq('gkg-indexer')
      end

      it 'attributes the download audit event to the Orbit indexer' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'repository_download_operation',
            author: an_instance_of(::Gitlab::Audit::OrbitIndexerAuthor)
          )
        )

        send_request(project_id: project.id)
      end

      it 'returns forbidden when the download is banned' do
        # Orbit authenticates as a service (no user), so stub the class-level check
        # directly to prove the endpoint still enforces the ban before serving.
        allow(::Users::Abuse::ProjectsDownloadBanCheckService)
          .to receive(:execute).and_return(ServiceResponse.error(message: 'banned'))

        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      context 'when ref is provided' do
        it 'sends a git archive for the given ref' do
          send_request(project_id: project.id, ref: project.default_branch_or_main)

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]).to start_with('git-archive:')
        end
      end

      context 'with include_lfs_blobs' do
        it 'resolves LFS pointers by default' do
          send_request(project_id: project.id)

          expect(sent_archive_request.include_lfs_blobs).to be(true)
        end

        it 'resolves LFS pointers when explicitly requested' do
          send_request(project_id: project.id, include_lfs_blobs: true)

          expect(sent_archive_request.include_lfs_blobs).to be(true)
        end

        it 'leaves LFS pointers unresolved when disabled' do
          send_request(project_id: project.id, include_lfs_blobs: false)

          expect(sent_archive_request.include_lfs_blobs).to be(false)
        end

        it 'treats a blank value as the default' do
          get api("/internal/orbit/project/#{project.id}/repository/archive"),
            params: { include_lfs_blobs: '' },
            headers: jwt_auth_headers

          expect(response).to have_gitlab_http_status(:ok)
          expect(sent_archive_request.include_lfs_blobs).to be(true)
        end

        it 'caches an archive without LFS objects under a different path' do
          send_request(project_id: project.id)
          resolved_path = sent_archive_params['ArchivePath']

          send_request(project_id: project.id, include_lfs_blobs: false)

          expect(sent_archive_params['ArchivePath']).not_to eq(resolved_path)
        end
      end

      context 'when ref does not exist' do
        it 'returns 404' do
          send_request(project_id: project.id, ref: 'nonexistent-ref')

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end

  describe 'GET /internal/orbit/project/:project_id/repository/changed_paths' do
    let_it_be(:project) { create(:project, :repository) }
    let(:default_left_revision) { project.repository.commit('HEAD~2').sha }
    let(:default_right_revision) { project.repository.commit('HEAD').sha }

    def send_request(
      project_id:, left_tree_revision: default_left_revision,
      right_tree_revision: default_right_revision, headers: jwt_auth_headers
    )
      get api("/internal/orbit/project/#{project_id}/repository/changed_paths"),
        params: { left_tree_revision: left_tree_revision, right_tree_revision: right_tree_revision },
        headers: headers
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'

    context 'when project exists' do
      it 'sends a changed paths response for a valid fast-forward range' do
        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]).to start_with('git-changed-paths:')
      end

      it 'forwards the client_name derived from the JWT subject' do
        send_request(project_id: project.id)

        encoded_params = response.headers[Gitlab::Workhorse::SEND_DATA_HEADER].delete_prefix('git-changed-paths:')
        decoded = Gitlab::Json.safe_parse(Base64.urlsafe_decode64(encoded_params))

        expect(decoded.dig('GitalyServer', 'call_metadata', 'client_name')).to eq('gkg-indexer')
      end

      context 'when left_tree_revision is not an ancestor of right_tree_revision (force push)' do
        it 'returns 400' do
          allow_any_instance_of(Repository).to receive(:ancestor?).and_return(false) # rubocop:disable RSpec/AnyInstanceOf -- need to stub the repo loaded inside the request

          send_request(project_id: project.id)

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('force push detected')
        end
      end

      context 'when left_tree_revision is a blank ref' do
        it 'skips ancestor check and succeeds' do
          send_request(project_id: project.id, left_tree_revision: Gitlab::Git::SHA1_BLANK_SHA)

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]).to start_with('git-changed-paths:')
        end
      end

      context 'when required params are missing' do
        it 'returns 400 when left_tree_revision is missing' do
          get api("/internal/orbit/project/#{project.id}/repository/changed_paths"),
            params: { right_tree_revision: default_right_revision },
            headers: jwt_auth_headers

          expect(response).to have_gitlab_http_status(:bad_request)
        end

        it 'returns 400 when right_tree_revision is missing' do
          get api("/internal/orbit/project/#{project.id}/repository/changed_paths"),
            params: { left_tree_revision: default_left_revision },
            headers: jwt_auth_headers

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end
    end
  end

  describe 'POST /internal/orbit/project/:project_id/repository/changed_paths' do
    let_it_be(:project) { create(:project, :repository) }
    let(:head_sha) { project.repository.commit('HEAD').sha }
    let(:base_sha) { project.repository.commit('HEAD~2').sha }
    let(:default_comparisons) { [{ base_revision: base_sha, target_revision: head_sha }] }
    let(:workhorse_payload) do
      encoded = response.headers.fetch(Gitlab::Workhorse::SEND_DATA_HEADER).delete_prefix('git-changed-paths:')
      Gitlab::Json::SafeParser.parse(Base64.urlsafe_decode64(encoded))
    end

    def send_request(project_id:, comparisons: default_comparisons, headers: jwt_auth_headers)
      post api("/internal/orbit/project/#{project_id}/repository/changed_paths"),
        params: Gitlab::Json.dump(comparisons: comparisons),
        headers: headers.merge('Content-Type' => 'application/json')
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'

    it 'compares commits in both directions and leaves unchanged targets empty', :aggregate_failures do
      unchanged_sha = project.repository.commit('HEAD~1').sha
      comparisons = [
        { base_revision: base_sha, target_revision: head_sha },
        { base_revision: head_sha, target_revision: base_sha },
        { base_revision: unchanged_sha, target_revision: unchanged_sha }
      ]

      send_request(project_id: project.id, comparisons: comparisons)

      expect(response).to have_gitlab_http_status(:ok)
      expect(workhorse_payload.dig('GitalyServer', 'call_metadata', 'client_name')).to eq('gkg-indexer')

      request = Gitaly::FindChangedPathsRequest.decode_json(workhorse_payload.fetch('FindChangedPathsRequest'))
      changes = Gitlab::GitalyClient.call(project.repository.storage, :diff_service, :find_changed_paths, request)
        .flat_map(&:paths).group_by(&:commit_id)

      expect(changes.keys).to match_array([head_sha, base_sha])
      expect(changes.fetch(head_sha).map { |change| [change.path, change.old_blob_id, change.new_blob_id] })
        .to match_array(changes.fetch(base_sha).map { |change| [change.path, change.new_blob_id, change.old_blob_id] })
    end

    it 'compares divergent branches without requiring either commit to be an ancestor', :aggregate_failures do
      user = create(:user)
      left_sha = project.repository.create_file(user, 'left.txt', 'left',
        message: 'Add left file', branch_name: 'orbit-left', start_branch_name: project.default_branch)
      right_sha = project.repository.create_file(user, 'right.txt', 'right',
        message: 'Add right file', branch_name: 'orbit-right', start_branch_name: project.default_branch)

      send_request(project_id: project.id,
        comparisons: [{ base_revision: left_sha.upcase, target_revision: right_sha.upcase }])

      expect(response).to have_gitlab_http_status(:ok)

      request = Gitaly::FindChangedPathsRequest.decode_json(workhorse_payload.fetch('FindChangedPathsRequest'))
      changes = Gitlab::GitalyClient.call(project.repository.storage, :diff_service, :find_changed_paths, request)
        .flat_map(&:paths)

      expect(changes.map { |change| [change.path, change.status, change.commit_id] }).to contain_exactly(
        ['left.txt', :DELETED, right_sha],
        ['right.txt', :ADDED, right_sha]
      )
    end

    it 'accepts the maximum number of comparisons' do
      comparisons = Array.new(described_class::MAX_CHANGED_PATHS_COMPARISONS) do |index|
        { base_revision: base_sha, target_revision: format('%040x', index + 1) }
      end

      send_request(project_id: project.id, comparisons: comparisons)

      expect(response).to have_gitlab_http_status(:ok)
      request = Gitaly::FindChangedPathsRequest.decode_json(workhorse_payload.fetch('FindChangedPathsRequest'))
      expect(request.requests.size).to eq(described_class::MAX_CHANGED_PATHS_COMPARISONS)
    end

    it 'rejects oversized batches' do
      oversized = default_comparisons * (described_class::MAX_CHANGED_PATHS_COMPARISONS + 1)

      send_request(project_id: project.id, comparisons: oversized)

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to include('comparisons is limited to 1000 entries')
    end

    it 'rejects repeated targets even when the bases or letter casing differ' do
      send_request(project_id: project.id, comparisons: [
        { base_revision: base_sha, target_revision: head_sha },
        { base_revision: head_sha, target_revision: head_sha.upcase }
      ])

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to include('target_revision must be unique')
    end

    [nil, [], [nil], [1], ['not-a-comparison'], [{}], [{ base_revision: nil, target_revision: nil }]]
      .each do |comparisons|
      it "rejects missing or empty comparisons: #{comparisons.inspect}" do
        send_request(project_id: project.id, comparisons: comparisons)

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    %i[base_revision target_revision].product([nil, '', ' ', 'main', 'a' * 7, 'a' * 41, 'g' * 40, '--all'])
      .each do |revision_field, invalid_revision|
      it "rejects #{invalid_revision.inspect} as #{revision_field}" do
        comparison = default_comparisons.first.merge(revision_field => invalid_revision)

        send_request(project_id: project.id, comparisons: [comparison])

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end
  end

  describe 'POST /internal/orbit/project/:project_id/repository/list_blobs' do
    let_it_be(:project) { create(:project, :repository) }
    let(:default_revisions) { [project.repository.commit('HEAD').sha] }

    def send_request(project_id:, revisions: default_revisions, bytes_limit: nil, headers: jwt_auth_headers)
      params = { revisions: revisions }
      params[:bytes_limit] = bytes_limit if bytes_limit

      post api("/internal/orbit/project/#{project_id}/repository/list_blobs"),
        params: params.to_json,
        headers: headers.merge('Content-Type' => 'application/json')
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'

    context 'when project exists' do
      it 'sends a list blobs response' do
        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]).to start_with('git-list-blobs:')
      end

      it 'forwards the client_name derived from the JWT subject' do
        send_request(project_id: project.id)

        encoded_params = response.headers[Gitlab::Workhorse::SEND_DATA_HEADER].delete_prefix('git-list-blobs:')
        decoded = Gitlab::Json.safe_parse(Base64.urlsafe_decode64(encoded_params))

        expect(decoded.dig('GitalyServer', 'call_metadata', 'client_name')).to eq('gkg-indexer')
      end

      it 'passes revisions through to workhorse' do
        to_sha = project.repository.commit('HEAD').sha
        from_sha = project.repository.commit('HEAD~2').sha

        send_request(project_id: project.id, revisions: [to_sha, '--not', from_sha])

        expect(response).to have_gitlab_http_status(:ok)
        header_value = response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]
        expect(header_value).to start_with('git-list-blobs:')

        encoded_params = header_value.delete_prefix('git-list-blobs:')
        decoded = Gitlab::Json.safe_parse(Base64.urlsafe_decode64(encoded_params))
        request_json = decoded['ListBlobsRequest']
        expect(request_json).to include(to_sha)
        expect(request_json).to include(from_sha)
      end

      context 'when bytes_limit is provided' do
        it 'passes the custom bytes_limit to workhorse' do
          custom_limit = 512

          send_request(project_id: project.id, bytes_limit: custom_limit)

          expect(response).to have_gitlab_http_status(:ok)
          header_value = response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]
          expect(header_value).to start_with('git-list-blobs:')

          encoded_params = header_value.delete_prefix('git-list-blobs:')
          decoded = Gitlab::Json.safe_parse(Base64.urlsafe_decode64(encoded_params))
          request_json = decoded['ListBlobsRequest']
          expect(request_json).to include("\"bytesLimit\":\"#{custom_limit}\"")
        end
      end

      context 'when bytes_limit is invalid' do
        it 'returns 400 for zero' do
          send_request(project_id: project.id, bytes_limit: 0)

          expect(response).to have_gitlab_http_status(:bad_request)
        end

        it 'returns 400 for negative values' do
          send_request(project_id: project.id, bytes_limit: -1)

          expect(response).to have_gitlab_http_status(:bad_request)
        end

        it 'returns 400 when exceeding the maximum' do
          send_request(project_id: project.id, bytes_limit: API::Internal::Orbit::BLOB_BYTES_LIMIT + 1)

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when revisions exceed the maximum' do
        it 'returns 400' do
          oversized_revisions = Array.new(described_class::MAX_LIST_BLOBS_REVISIONS + 1) { |i| "sha#{i}" }

          send_request(project_id: project.id, revisions: oversized_revisions)

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(response.body)
            .to include("revisions is limited to #{described_class::MAX_LIST_BLOBS_REVISIONS} entries")
        end
      end

      context 'when revisions are at the maximum' do
        it 'does not reject the request' do
          max_revisions = Array.new(described_class::MAX_LIST_BLOBS_REVISIONS) { |i| "sha#{i}" }

          send_request(project_id: project.id, revisions: max_revisions)

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when revisions param is missing' do
        it 'returns 400' do
          post api("/internal/orbit/project/#{project.id}/repository/list_blobs"),
            params: {}.to_json,
            headers: jwt_auth_headers.merge('Content-Type' => 'application/json')

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end
    end
  end

  describe 'GET /internal/orbit/project/:project_id/repository/commits' do
    let_it_be(:project) { create(:project, :repository) }

    def send_request(project_id:, params: {}, headers: jwt_auth_headers)
      get api("/internal/orbit/project/#{project_id}/repository/commits"),
        params: params,
        headers: headers
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'
    include_examples 'repository pagination bounds'

    context 'when project exists' do
      it 'returns commits for the default branch' do
        send_request(project_id: project.id, params: { per_page: 5 })

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to be_an(Array)
        expect(json_response.size).to be <= 5
        expect(json_response.first).to include('id', 'short_id', 'title', 'message', 'author_name', 'authored_date')
      end

      it 'paginates results using cursor' do
        send_request(project_id: project.id, params: { per_page: 2 })
        first_page = json_response
        next_token = response.headers['X-Next-Page-Token']

        expect(first_page.size).to eq(2)
        expect(next_token).to be_present

        send_request(project_id: project.id, params: { per_page: 2, page_token: next_token })
        second_page = json_response

        expect(second_page).not_to be_empty
        expect(first_page.pluck('id')).not_to eq(second_page.pluck('id'))
      end

      context 'when ref is provided' do
        it 'returns commits for the given ref' do
          send_request(
            project_id: project.id,
            params: { ref: project.default_branch_or_main, per_page: 3 }
          )

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response.size).to be <= 3
        end
      end

      context 'when ref_name is provided' do
        it 'returns commits for the given ref' do
          send_request(
            project_id: project.id,
            params: { ref_name: project.default_branch_or_main, per_page: 3 }
          )

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response.size).to be <= 3
        end
      end

      it 'rejects ref and ref_name together' do
        send_request(
          project_id: project.id,
          params: {
            ref: project.default_branch_or_main,
            ref_name: project.default_branch_or_main
          }
        )

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('ref and ref_name cannot be used together')
      end

      it 'paginates a pinned first-parent history without including merged side commits', :aggregate_failures do
        head = project.repository.commit
        expected_commits = []
        commit = head
        while commit
          expected_commits << commit.sha
          commit = commit.parents.first
        end

        commits = []
        page_token = nil
        loop do
          send_request(project_id: project.id,
            params: { ref: head.sha, first_parent: true, per_page: 5, page_token: page_token })

          expect(response).to have_gitlab_http_status(:ok)
          commits.concat(json_response.pluck('id'))
          page_token = response.headers['X-Next-Page-Token']
          break if page_token.blank?
        end

        expect(commits).to eq(expected_commits)
        expect(commits.size).to be < project.repository.commits(head.sha, limit: 100).size
      end

      it 'avoids N+1 queries' do
        send_request(project_id: project.id, params: { per_page: 2 })

        control = ActiveRecord::QueryRecorder.new do
          send_request(project_id: project.id, params: { per_page: 2 })
        end

        # More commits than the per_page: 2 baseline should not increase query count.
        expect do
          send_request(project_id: project.id, params: { per_page: 5 })
        end.not_to exceed_query_limit(control)
      end

      context 'when ref does not exist' do
        it 'returns 400' do
          send_request(project_id: project.id, params: { ref: 'nonexistent-branch' })

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when the request times out' do
        before do
          allow_any_instance_of(Repository).to receive(:list_commits) # rubocop:disable RSpec/AnyInstanceOf -- need to stub the repo loaded inside the request
            .and_raise(Gitlab::Git::CommandTimedOut)
        end

        it 'returns 500' do
          send_request(project_id: project.id)

          expect(response).to have_gitlab_http_status(:internal_server_error)
        end
      end

      context 'when since filter is provided' do
        it 'returns only commits after the given date' do
          recent_commit = project.repository.commit('HEAD')
          send_request(project_id: project.id, params: { since: recent_commit.committed_date.iso8601 })

          expect(response).to have_gitlab_http_status(:ok)
          json_response.each do |commit|
            expect(Time.parse(commit['committed_date'])).to be >= recent_commit.committed_date
          end
        end
      end

      context 'when until filter is provided' do
        it 'returns only commits before the given date' do
          cutoff = 1.year.ago
          send_request(project_id: project.id, params: { until: cutoff.iso8601 })

          expect(response).to have_gitlab_http_status(:ok)
          json_response.each do |commit|
            expect(Time.parse(commit['committed_date'])).to be <= cutoff
          end
        end
      end

      context 'when all commits fit in a single page' do
        let_it_be(:small_project) { create(:project, :small_repo) }

        it 'does not include the next page token header' do
          send_request(project_id: small_project.id, params: { per_page: 100 })

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.headers['X-Next-Page-Token']).to be_nil
        end
      end
    end
  end

  describe 'GET /internal/orbit/project/:project_id/merge_requests/:merge_request_iid/raw_diffs' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    def send_request(project_id:, merge_request_iid: merge_request.iid, headers: jwt_auth_headers)
      get api("/internal/orbit/project/#{project_id}/merge_requests/#{merge_request_iid}/raw_diffs"),
        headers: headers
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'

    context 'when merge request exists' do
      it 'sends a git diff response via Workhorse' do
        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]).to start_with('git-diff:')
      end
    end

    context 'when merge request has no diff refs' do
      it 'returns 404' do
        allow_any_instance_of(MergeRequest).to receive(:diff_refs).and_return(nil) # rubocop:disable RSpec/AnyInstanceOf -- needed to stub the found record

        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:not_found)
        expect(response.body).to include('merge_request has no diff refs')
      end
    end

    context 'when merge request does not exist' do
      it 'returns 404' do
        send_request(project_id: project.id, merge_request_iid: non_existing_record_iid)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when merge request belongs to a different project' do
      let_it_be(:other_project) { create(:project, :repository) }

      it 'returns 404' do
        send_request(project_id: other_project.id)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'GET /internal/orbit/project/:project_id/merge_request_diffs/:diff_id' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:merge_request) { create(:merge_request, :skip_diff_creation, source_project: project) }
    let_it_be(:diff_record) { create(:merge_request_diff, merge_request: merge_request) }
    let_it_be(:diff_file) do
      create(:merge_request_diff_file, merge_request_diff: diff_record,
        new_path: 'app/models/user.rb', old_path: 'app/models/user.rb',
        diff: "@@ -1,3 +1,4 @@\n class User\n+  validates :name\n end\n",
        new_file: false, a_mode: '100644', b_mode: '100644')
    end

    let_it_be(:diff_file_2) do
      create(:merge_request_diff_file, merge_request_diff: diff_record,
        new_path: 'README.md', old_path: 'README.md',
        diff: "@@ -1 +1 @@\n-Old readme\n+New readme\n",
        new_file: false, a_mode: '100644', b_mode: '100644', relative_order: 1)
    end

    def send_request(project_id:, diff_id: diff_record.id, paths: nil, headers: jwt_auth_headers)
      params = {}
      params[:paths] = paths if paths

      get api("/internal/orbit/project/#{project_id}/merge_request_diffs/#{diff_id}"),
        params: params,
        headers: headers
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'

    context 'when diff record exists' do
      it 'returns per-file diffs with metadata' do
        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['id']).to eq(diff_record.id)
        expect(json_response['head_commit_sha']).to eq(diff_record.head_commit_sha)
        expect(json_response['base_commit_sha']).to eq(diff_record.base_commit_sha)
        expect(json_response['start_commit_sha']).to eq(diff_record.start_commit_sha)
        expect(json_response['diffs']).to be_an(Array)
        expect(json_response['diffs'].size).to eq(2)

        first_diff = json_response['diffs'].find { |d| d['new_path'] == 'app/models/user.rb' }
        expect(first_diff['diff']).to include('validates :name')
        expect(first_diff['new_file']).to be(false)
      end
    end

    context 'when diff has more than 100 files' do
      it 'limits response to 100 diffs' do
        large_diffs = Array.new(101) do |i|
          Gitlab::Git::Diff.new({
            diff: "@@ -1 +1 @@\n-old\n+new\n",
            new_path: "file_#{i}.rb",
            old_path: "file_#{i}.rb",
            a_mode: '100644',
            b_mode: '100644',
            new_file: false
          })
        end
        allow_any_instance_of(MergeRequestDiff).to receive(:raw_diffs).and_return(large_diffs) # rubocop:disable RSpec/AnyInstanceOf -- needed to stub the found record

        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['diffs'].size).to eq(100)
      end
    end

    context 'when paths filter is provided' do
      it 'returns only matching files' do
        send_request(project_id: project.id, paths: ['README.md'])

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['diffs'].size).to eq(1)
        expect(json_response['diffs'].first['new_path']).to eq('README.md')
      end
    end

    context 'when paths exceed limit' do
      it 'returns 400' do
        send_request(project_id: project.id, paths: Array.new(101) { |i| "file#{i}.rb" })

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(response.body).to include('paths limited to 100 entries')
      end
    end

    context 'when diff_id does not exist' do
      it 'returns 404' do
        send_request(project_id: project.id, diff_id: non_existing_record_id)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when diff belongs to a different project' do
      let_it_be(:other_project) { create(:project, :repository) }

      it 'returns 404' do
        send_request(project_id: other_project.id, diff_id: diff_record.id)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'GET /internal/orbit/project/:project_id/merge_request_diffs/:diff_id/raw_diffs' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:merge_request) { create(:merge_request, :skip_diff_creation, source_project: project) }
    let_it_be(:diff_record) { create(:merge_request_diff, merge_request: merge_request) }
    let_it_be(:diff_file) do
      create(:merge_request_diff_file, merge_request_diff: diff_record,
        new_path: 'app/models/user.rb', old_path: 'app/models/user.rb',
        diff: "@@ -1,3 +1,4 @@\n class User\n+  validates :name\n end\n",
        new_file: false, a_mode: '100644', b_mode: '100644')
    end

    def send_request(project_id:, diff_id: diff_record.id, headers: jwt_auth_headers)
      get api("/internal/orbit/project/#{project_id}/merge_request_diffs/#{diff_id}/raw_diffs"),
        headers: headers
    end

    include_examples 'authorization'
    include_examples 'feature flag check'
    include_examples 'project not found'

    context 'when diff record exists' do
      it 'sends a git diff response via Workhorse' do
        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]).to start_with('git-diff:')
      end
    end

    context 'when diff record has no diff refs' do
      it 'returns 404' do
        allow_any_instance_of(MergeRequestDiff).to receive(:diff_refs).and_return(nil) # rubocop:disable RSpec/AnyInstanceOf -- needed to stub the found record

        send_request(project_id: project.id)

        expect(response).to have_gitlab_http_status(:not_found)
        expect(response.body).to include('merge_request_diff has no diff refs')
      end
    end

    context 'when diff_id does not exist' do
      it 'returns 404' do
        send_request(project_id: project.id, diff_id: non_existing_record_id)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when diff belongs to a different project' do
      let_it_be(:other_project) { create(:project, :repository) }

      it 'returns 404' do
        send_request(project_id: other_project.id, diff_id: diff_record.id)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
