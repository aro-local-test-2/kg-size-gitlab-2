# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Duo Agent Platform session <-> pipeline links', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }

  # The pipeline the fix_pipeline flow was initiated against.
  let_it_be(:source_pipeline) { create(:ci_pipeline, project: project) }

  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  let_it_be(:source_link) do
    create(:duo_workflows_workflow_pipeline, workflow: workflow, pipeline: source_pipeline, link_type: :source)
  end

  let(:current_user) { user }

  before do
    stub_licensed_features(ai_workflows: true)
    # Make read_duo_workflow pass for the workflow owner, matching WorkflowPolicy's
    # owner rule. The link type delegates to the workflow for the same ability.
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow_any_instance_of(User).to receive(:allowed_to_use?).and_return(true) # rubocop:disable RSpec/AnyInstanceOf -- current_user identity differs across the request
  end

  context 'when querying a pipeline for its linked sessions' do
    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{source_pipeline.iid}") {
              duoWorkflowLinks {
                nodes {
                  linkType
                  workflow { id }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns the linked sessions' do
      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(graphql_errors).to be_nil

      workflow_links = graphql_data_at(:project, :pipeline, :duo_workflow_links, :nodes)
      expect(workflow_links).to contain_exactly(
        { 'linkType' => 'SOURCE', 'workflow' => { 'id' => workflow.to_gid.to_s } }
      )
    end
  end

  context 'when querying a session for its linked pipelines' do
    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{source_pipeline.iid}") {
              duoWorkflowLinks {
                nodes {
                  linkType
                  workflow {
                    pipelineLinks {
                      nodes {
                        linkType
                        pipeline { id }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'traverses pipeline -> sessions -> pipelines' do
      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(graphql_errors).to be_nil

      workflow_links = graphql_data_at(:project, :pipeline, :duo_workflow_links, :nodes)
      expect(workflow_links.pluck('linkType')).to contain_exactly('SOURCE')

      downstream = workflow_links.first.dig('workflow', 'pipelineLinks', 'nodes')
      expect(downstream).to contain_exactly(
        { 'linkType' => 'SOURCE', 'pipeline' => { 'id' => source_pipeline.to_gid.to_s } }
      )
    end
  end

  # The `link_type` enum currently has only one value (`source`), so filtering cannot
  # exclude anything and the result matches the unfiltered query above. When a second
  # type is added, create a link of that type here and assert it is excluded.
  context 'with a link_type filter on the session links' do
    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{source_pipeline.iid}") {
              duoWorkflowLinks {
                nodes {
                  workflow {
                    pipelineLinks(linkType: SOURCE) {
                      nodes {
                        linkType
                        pipeline { id }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns only links of the requested type' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil

      downstream = graphql_data_at(:project, :pipeline, :duo_workflow_links, :nodes)
        .first.dig('workflow', 'pipelineLinks', 'nodes')

      expect(downstream).to contain_exactly(
        { 'linkType' => 'SOURCE', 'pipeline' => { 'id' => source_pipeline.to_gid.to_s } }
      )
    end
  end

  context 'when the pipeline has no linked sessions' do
    let_it_be(:lonely_pipeline) { create(:ci_pipeline, project: project) }

    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{lonely_pipeline.iid}") {
              duoWorkflowLinks { nodes { linkType } }
            }
          }
        }
      GRAPHQL
    end

    it 'returns an empty list of links' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project, :pipeline, :duo_workflow_links, :nodes)).to be_empty
    end
  end

  context 'with multiple linked sessions' do
    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{source_pipeline.iid}") {
              duoWorkflowLinks {
                nodes {
                  linkType
                  workflow { id humanStatus }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'does not N+1 on the per-session authorization' do
      post_graphql(query, current_user: current_user) # warm up one-time setup queries
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }
      expect(graphql_errors).to be_nil

      # Another session, owned by the same user, also linked to the source pipeline.
      other_workflow = create(:duo_workflows_workflow, project: project, user: user)
      create(:duo_workflows_workflow_pipeline, workflow: other_workflow, pipeline: source_pipeline, link_type: :source)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
      expect(graphql_data_at(:project, :pipeline, :duoWorkflowLinks, :nodes).count).to eq(2)
    end
  end

  context 'with multiple pipelines linked to the session' do
    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{source_pipeline.iid}") {
              duoWorkflowLinks {
                nodes {
                  workflow {
                    pipelineLinks {
                      nodes {
                        linkType
                        pipeline { id }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'does not N+1 on the linked pipelines' do
      post_graphql(query, current_user: current_user) # warm up one-time setup queries
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }
      expect(graphql_errors).to be_nil

      extra_pipeline = create(:ci_pipeline, project: project)
      create(:duo_workflows_workflow_pipeline, workflow: workflow, pipeline: extra_pipeline, link_type: :source)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
    end
  end

  context 'with a granular personal access token' do
    # The traversal crosses granular boundaries: ProjectType authorizes `read_project`
    # and Ci::PipelineType authorizes `read_pipeline`, both at the :project boundary,
    # while DuoWorkflowPipelineLink authorizes `read_duo_workflow` at the :user boundary.
    let(:read_pipeline_scope) do
      build(:granular_scope, boundary: ::Authz::Boundary.for(project),
        permissions: [assignable_name(:read_project), assignable_name(:read_pipeline)])
    end

    let(:read_duo_workflow_scope) do
      build(:granular_scope, boundary: ::Authz::Boundary.for(:user), organization: project.organization,
        permissions: [assignable_name(:read_duo_workflow)])
    end

    let(:token_scopes) { [read_pipeline_scope, read_duo_workflow_scope] }

    let(:pat) do
      create(:granular_pat, user: user, organization: project.organization).tap do |token|
        token_scopes.each do |scope|
          create(:personal_access_token_granular_scope,
            personal_access_token: token, granular_scope: scope, organization: project.organization)
        end
      end
    end

    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{source_pipeline.iid}") {
              duoWorkflowLinks {
                nodes { linkType }
              }
            }
          }
        }
      GRAPHQL
    end

    subject(:links) { graphql_data_at(:project, :pipeline, :duo_workflow_links, :nodes) }

    def assignable_name(permission)
      ::Authz::PermissionGroups::Assignable.for_permission(permission).first.name
    end

    it 'returns the linked sessions' do
      post_graphql(query, token: { personal_access_token: pat })

      expect(graphql_errors).to be_nil
      expect(links.pluck('linkType')).to contain_exactly('SOURCE')
    end

    context 'when the token is missing the read_duo_workflow scope' do
      let(:token_scopes) { [read_pipeline_scope] }

      it 'reads the pipeline but omits its session links' do
        post_graphql(query, token: { personal_access_token: pat })

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:project, :pipeline)).to be_present
        expect(links).to be_empty
      end
    end

    context 'when the `granular_personal_access_tokens` feature flag is disabled' do
      before do
        stub_feature_flags(granular_personal_access_tokens: false)
      end

      it 'denies access' do
        post_graphql(query, token: { personal_access_token: pat })

        expect(graphql_data_at(:project)).to be_nil
      end
    end
  end

  describe 'granular personal access token authorization' do
    # A public project lets the token pass the parent project and pipeline
    # authorization via the public-access bypass, so the test gates on
    # DuoWorkflowPipelineLink's `read_duo_workflow` permission at the user boundary.
    let_it_be(:public_project) { create(:project, :public) }
    let_it_be(:public_pipeline) { create(:ci_pipeline, project: public_project) }
    let_it_be(:public_workflow) { create(:duo_workflows_workflow, project: public_project, user: user) }

    let_it_be(:public_link) do
      create(:duo_workflows_workflow_pipeline, workflow: public_workflow, pipeline: public_pipeline,
        link_type: :source)
    end

    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{public_project.full_path}") {
            pipeline(iid: "#{public_pipeline.iid}") {
              duoWorkflowLinks {
                nodes { linkType }
              }
            }
          }
        }
      GRAPHQL
    end

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(public_project, :duo_workflow).and_return(true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_duo_workflow do
      let(:boundary_object) { :user }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end
  end

  context 'when the user cannot read the linked session' do
    let_it_be(:other_user) { create(:user, developer_of: project) }
    let(:current_user) { other_user }

    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{source_pipeline.iid}") {
              duoWorkflowLinks { nodes { linkType } }
            }
          }
        }
      GRAPHQL
    end

    it 'omits the link from the pipeline' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project, :pipeline, :duo_workflow_links, :nodes)).to be_empty
    end
  end

  context 'when the pipeline is linked to sessions not all of which the user can read' do
    let_it_be(:other_user) { create(:user, developer_of: project) }
    let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project, user: other_user) }

    let_it_be(:redacted_link) do
      create(:duo_workflows_workflow_pipeline, workflow: other_workflow, pipeline: source_pipeline,
        link_type: :source)
    end

    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{source_pipeline.iid}") {
              duoWorkflowLinks {
                nodes {
                  linkType
                  workflow { id }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns only the links to sessions the user can read' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil

      linked_workflows = graphql_data_at(:project, :pipeline, :duo_workflow_links, :nodes)
        .map { |node| node.dig('workflow', 'id') }
      expect(linked_workflows).to contain_exactly(workflow.to_gid.to_s)
    end
  end
end
