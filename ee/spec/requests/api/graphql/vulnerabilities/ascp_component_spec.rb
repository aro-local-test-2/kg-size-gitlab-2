# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.vulnerability.ascpComponent', feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, security_dashboard_projects: [project]) }
  let_it_be(:scan) { create(:security_ascp_scan, project: project) }
  let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }

  let_it_be(:component) do
    create(:security_ascp_component, project: project, scan: scan,
      title: 'Auth Module', sub_directory: 'app/services/auth')
  end

  let_it_be(:security_context) do
    create(:security_ascp_security_context, :with_guidelines,
      project: project, scan: scan, component: component)
  end

  # The link is keyed on `vulnerabilities.finding_id`, which the factory populates with a
  # different record than `Vulnerability#finding` (`findings.first`).
  let_it_be(:link) do
    create(:vulnerability_finding_ascp_component_link,
      project: project,
      vulnerability_finding: vulnerability.vulnerability_finding,
      ascp_component: component)
  end

  let(:fields) do
    <<~QUERY
      ascpComponent {
        id
        title
        subDirectory
        securityContext {
          id
          summary
          authenticationModel
          securityGuidelines {
            nodes {
              id
              name
              severityIfViolated
            }
          }
        }
      }
    QUERY
  end

  let(:query) { graphql_query_for('vulnerability', { id: global_id_of(vulnerability) }, fields) }

  subject(:ascp_component) { graphql_data.dig('vulnerability', 'ascpComponent') }

  before_all do
    project.add_developer(user)
  end

  before do
    stub_licensed_features(security_dashboard: true)
  end

  context 'when the finding is matched to a component' do
    before do
      post_graphql(query, current_user: user)
    end

    it 'returns the component with its nested security context and guidelines' do
      guideline = security_context.guidelines.first

      expect(graphql_errors).to be_blank
      expect(ascp_component).to match(
        'id' => component.to_global_id.to_s,
        'title' => 'Auth Module',
        'subDirectory' => 'app/services/auth',
        'securityContext' => {
          'id' => security_context.to_global_id.to_s,
          'summary' => security_context.summary,
          'authenticationModel' => security_context.authentication_model,
          'securityGuidelines' => {
            'nodes' => [
              {
                'id' => guideline.to_global_id.to_s,
                'name' => guideline.name,
                'severityIfViolated' => guideline.severity_if_violated.upcase
              }
            ]
          }
        }
      )
    end
  end

  context 'when the finding is not matched to a component' do
    let_it_be(:unmatched_vulnerability) { create(:vulnerability, :with_finding, project: project) }

    let(:query) { graphql_query_for('vulnerability', { id: global_id_of(unmatched_vulnerability) }, fields) }

    it 'returns nil without an error' do
      post_graphql(query, current_user: user)

      expect(graphql_errors).to be_blank
      expect(ascp_component).to be_nil
    end
  end

  context 'when the component has no security context' do
    let_it_be(:bare_vulnerability) { create(:vulnerability, :with_finding, project: project) }
    let_it_be(:bare_component) { create(:security_ascp_component, project: project, scan: scan) }
    let_it_be(:bare_link) do
      create(:vulnerability_finding_ascp_component_link,
        project: project,
        vulnerability_finding: bare_vulnerability.vulnerability_finding,
        ascp_component: bare_component)
    end

    let(:query) { graphql_query_for('vulnerability', { id: global_id_of(bare_vulnerability) }, fields) }

    it 'returns the component with a nil security context' do
      post_graphql(query, current_user: user)

      expect(graphql_errors).to be_blank
      expect(ascp_component['securityContext']).to be_nil
    end
  end

  context 'when the security context has no guidelines' do
    let_it_be(:other_vulnerability) { create(:vulnerability, :with_finding, project: project) }
    let_it_be(:other_component) { create(:security_ascp_component, project: project, scan: scan) }
    let_it_be(:other_context) do
      create(:security_ascp_security_context, project: project, scan: scan, component: other_component)
    end

    let_it_be(:other_link) do
      create(:vulnerability_finding_ascp_component_link,
        project: project,
        vulnerability_finding: other_vulnerability.vulnerability_finding,
        ascp_component: other_component)
    end

    let(:query) { graphql_query_for('vulnerability', { id: global_id_of(other_vulnerability) }, fields) }

    it 'returns an empty guidelines list' do
      post_graphql(query, current_user: user)

      expect(graphql_errors).to be_blank
      expect(ascp_component.dig('securityContext', 'securityGuidelines', 'nodes')).to be_empty
    end
  end

  context 'when the ascp_component_vulnerability_association feature flag is disabled' do
    before do
      stub_feature_flags(ascp_component_vulnerability_association: false)
      post_graphql(query, current_user: user)
    end

    it 'returns nil even though the link exists' do
      expect(graphql_errors).to be_blank
      expect(ascp_component).to be_nil
    end

    it 'still resolves the other vulnerability fields' do
      post_graphql(graphql_query_for('vulnerability', { id: global_id_of(vulnerability) }, 'title'),
        current_user: user)

      expect(graphql_data.dig('vulnerability', 'title')).to eq(vulnerability.title)
    end
  end

  describe 'authorization' do
    context 'when the user cannot read the ASCP component' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_ascp_component, anything).and_return(false)

        post_graphql(graphql_query_for('vulnerability', { id: global_id_of(vulnerability) },
          "title\n#{fields}"), current_user: user)
      end

      it 'returns nil for the component but still resolves sibling fields' do
        expect(graphql_errors).to be_blank
        expect(ascp_component).to be_nil
        expect(graphql_data.dig('vulnerability', 'title')).to eq(vulnerability.title)
      end
    end

    context 'when the user is a guest' do
      let_it_be(:guest) { create(:user, guest_of: project) }

      it 'returns no vulnerability' do
        post_graphql(query, current_user: guest)

        expect(graphql_data['vulnerability']).to be_nil
      end
    end

    context 'when the user is anonymous' do
      it 'returns no vulnerability' do
        post_graphql(query, current_user: nil)

        expect(graphql_data['vulnerability']).to be_nil
      end
    end
  end

  describe 'licensing' do
    context 'when security_dashboard is not licensed' do
      before do
        stub_licensed_features(security_dashboard: false)
        post_graphql(query, current_user: user)
      end

      it 'returns no vulnerability' do
        expect(graphql_errors).to be_blank
        expect(graphql_data['vulnerability']).to be_nil
      end
    end
  end

  describe 'N+1 queries' do
    let(:list_query) do
      <<~QUERY
        {
          project(fullPath: "#{project.full_path}") {
            vulnerabilities {
              nodes {
                #{fields}
              }
            }
          }
        }
      QUERY
    end

    def create_matched_vulnerability
      other_vulnerability = create(:vulnerability, :with_finding, project: project)
      other_component = create(:security_ascp_component, project: project, scan: scan)
      create(:security_ascp_security_context, :with_guidelines,
        project: project, scan: scan, component: other_component)
      create(:vulnerability_finding_ascp_component_link,
        project: project,
        vulnerability_finding: other_vulnerability.vulnerability_finding,
        ascp_component: other_component)
    end

    it 'does not increase with the number of matched vulnerabilities' do
      post_graphql(list_query, current_user: user)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(list_query, current_user: user)
      end

      2.times { create_matched_vulnerability }

      expect { post_graphql(list_query, current_user: user) }
        .to issue_same_number_of_queries_as(control).or_fewer

      nodes = graphql_data.dig('project', 'vulnerabilities', 'nodes')
      expect(nodes.count { |node| node['ascpComponent'].present? }).to eq(3)
    end

    it 'does not increase when only some vulnerabilities are matched' do
      create(:vulnerability, :with_finding, project: project)

      post_graphql(list_query, current_user: user)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(list_query, current_user: user)
      end

      create(:vulnerability, :with_finding, project: project)
      create_matched_vulnerability

      expect { post_graphql(list_query, current_user: user) }
        .to issue_same_number_of_queries_as(control).or_fewer

      nodes = graphql_data.dig('project', 'vulnerabilities', 'nodes')
      expect(nodes).to include(a_hash_including('ascpComponent' => nil))
      expect(nodes.count { |node| node['ascpComponent'].present? }).to eq(2)
    end
  end
end
