# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Scan profiles (GraphQL fixtures)', feature_category: :security_testing_configuration do
  describe GraphQL::Query, type: :request do
    include ApiHelpers
    include GraphqlHelpers
    include JavaScriptFixturesHelpers

    create_path = 'security_configuration/graphql/scan_profiles/security_scan_profile_create.mutation.graphql'
    update_path = 'security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql'

    let_it_be(:current_user, freeze: false) { create(:user) }
    let_it_be(:root_group, freeze: false) { create(:group) }

    let(:secure_analyzers_prefix) { 'registry.gitlab.com/security-products' }
    let(:configuration) { { secureAnalyzersPrefix: secure_analyzers_prefix, historicScan: true } }

    let(:unset_configuration) do
      {
        'secureAnalyzersPrefix' => nil,
        'imageSuffix' => nil,
        'historicScan' => nil,
        'logOptions' => nil,
        'excludedPaths' => nil,
        'rulesetGitReference' => nil
      }
    end

    let(:fanned_out_configuration) do
      unset_configuration.merge('secureAnalyzersPrefix' => secure_analyzers_prefix, 'historicScan' => true)
    end

    before_all do
      root_group.add_maintainer(current_user)
    end

    before do
      stub_licensed_features(security_scan_profiles: true)
    end

    def create_secret_detection_profile
      profile = create(:security_scan_profile,
        namespace: root_group, scan_type: :secret_detection, name: 'Secret detection')

      %i[merge_request_pipeline default_branch_pipeline git_push_event].each do |trigger_type|
        create(:security_scan_profile_trigger,
          scan_profile: profile, namespace: root_group, trigger_type: trigger_type)
      end

      profile
    end

    def configuration_by_trigger(mutation)
      graphql_data_at(mutation, :scanProfile, :triggerSettings).to_h do |setting|
        [setting['triggerType'], setting['configuration'].except('__typename')]
      end
    end

    describe 'create' do
      it "graphql/#{create_path}.json" do
        query = get_graphql_query_as_string(create_path, ee: true)

        post_graphql(query, current_user: current_user, variables: {
          input: {
            namespaceId: root_group.to_global_id.to_s,
            scanType: 'SECRET_DETECTION',
            name: 'Nightly secret detection',
            description: 'Scans the default branch overnight',
            stripDefaults: false,
            triggers: [
              { triggerType: 'MERGE_REQUEST_PIPELINE', configuration: { secretDetection: configuration } },
              { triggerType: 'DEFAULT_BRANCH_PIPELINE', configuration: { secretDetection: configuration } },
              { triggerType: 'GIT_PUSH_EVENT' }
            ]
          }
        })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:securityScanProfileCreate, :errors)).to be_empty
        expect(graphql_data_at(:securityScanProfileCreate, :scanProfile)).to include(
          'name' => 'Nightly secret detection',
          'description' => 'Scans the default branch overnight',
          'scanType' => 'SECRET_DETECTION',
          'gitlabRecommended' => false,
          'triggers' => match_array(%w[MERGE_REQUEST_PIPELINE DEFAULT_BRANCH_PIPELINE GIT_PUSH_EVENT])
        )
        expect(configuration_by_trigger(:securityScanProfileCreate)).to eq(
          'MERGE_REQUEST_PIPELINE' => fanned_out_configuration,
          'DEFAULT_BRANCH_PIPELINE' => fanned_out_configuration,
          'GIT_PUSH_EVENT' => unset_configuration
        )
      end
    end

    describe 'update with profile-level variables' do
      it "graphql/#{update_path}.json" do
        profile = create_secret_detection_profile
        query = get_graphql_query_as_string(update_path, ee: true)

        post_graphql(query, current_user: current_user, variables: {
          input: {
            id: profile.to_global_id.to_s,
            stripDefaults: false,
            triggers: [
              { triggerType: 'MERGE_REQUEST_PIPELINE', configuration: { secretDetection: configuration } },
              { triggerType: 'DEFAULT_BRANCH_PIPELINE', configuration: { secretDetection: configuration } },
              { triggerType: 'GIT_PUSH_EVENT' }
            ]
          }
        })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:securityScanProfileUpdate, :errors)).to be_empty
        expect(graphql_data_at(:securityScanProfileUpdate, :scanProfile)).to include(
          'name' => 'Secret detection',
          'description' => 'This is a test scan profile'
        )
        expect(configuration_by_trigger(:securityScanProfileUpdate)).to eq(
          'MERGE_REQUEST_PIPELINE' => fanned_out_configuration,
          'DEFAULT_BRANCH_PIPELINE' => fanned_out_configuration,
          'GIT_PUSH_EVENT' => unset_configuration
        )
        expect(profile.reload.scan_profile_triggers.map(&:trigger_type))
          .to match_array(%w[merge_request_pipeline default_branch_pipeline git_push_event])
      end
    end

    describe 'update with per-trigger variables' do
      it "graphql/#{update_path}.per_trigger.json" do
        profile = create_secret_detection_profile
        query = get_graphql_query_as_string(update_path, ee: true)

        post_graphql(query, current_user: current_user, variables: {
          input: {
            id: profile.to_global_id.to_s,
            stripDefaults: false,
            triggers: [
              {
                triggerType: 'MERGE_REQUEST_PIPELINE',
                configuration: { secretDetection: { historicScan: false, excludedPaths: ['spec/fixtures/**'] } }
              },
              {
                triggerType: 'DEFAULT_BRANCH_PIPELINE',
                configuration: { secretDetection: { historicScan: true } }
              },
              { triggerType: 'GIT_PUSH_EVENT' }
            ]
          }
        })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:securityScanProfileUpdate, :errors)).to be_empty
        expect(configuration_by_trigger(:securityScanProfileUpdate)).to eq(
          'MERGE_REQUEST_PIPELINE' => unset_configuration.merge(
            'historicScan' => false, 'excludedPaths' => ['spec/fixtures/**']
          ),
          'DEFAULT_BRANCH_PIPELINE' => unset_configuration.merge('historicScan' => true),
          'GIT_PUSH_EVENT' => unset_configuration
        )
      end
    end

    describe 'update with both profile-level and trigger-level variables' do
      it "graphql/#{update_path}.merged.json" do
        profile = create_secret_detection_profile
        query = get_graphql_query_as_string(update_path, ee: true)

        post_graphql(query, current_user: current_user, variables: {
          input: {
            id: profile.to_global_id.to_s,
            stripDefaults: false,
            triggers: [
              {
                triggerType: 'MERGE_REQUEST_PIPELINE',
                configuration: { secretDetection: configuration.merge(historicScan: false) }
              },
              { triggerType: 'DEFAULT_BRANCH_PIPELINE', configuration: { secretDetection: configuration } },
              { triggerType: 'GIT_PUSH_EVENT' }
            ]
          }
        })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:securityScanProfileUpdate, :errors)).to be_empty
        expect(configuration_by_trigger(:securityScanProfileUpdate)).to eq(
          'MERGE_REQUEST_PIPELINE' => fanned_out_configuration.merge('historicScan' => false),
          'DEFAULT_BRANCH_PIPELINE' => fanned_out_configuration,
          'GIT_PUSH_EVENT' => unset_configuration
        )
      end
    end

    describe 'update with a trigger toggled off' do
      it "graphql/#{update_path}.toggled_off.json" do
        profile = create_secret_detection_profile
        query = get_graphql_query_as_string(update_path, ee: true)

        post_graphql(query, current_user: current_user, variables: {
          input: {
            id: profile.to_global_id.to_s,
            stripDefaults: false,
            triggers: [
              { triggerType: 'MERGE_REQUEST_PIPELINE', configuration: { secretDetection: configuration } },
              { triggerType: 'GIT_PUSH_EVENT' }
            ]
          }
        })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:securityScanProfileUpdate, :errors)).to be_empty
        expect(configuration_by_trigger(:securityScanProfileUpdate)).to eq(
          'MERGE_REQUEST_PIPELINE' => fanned_out_configuration,
          'GIT_PUSH_EVENT' => unset_configuration
        )
        expect(graphql_data_at(:securityScanProfileUpdate, :scanProfile, :triggers))
          .to match_array(%w[MERGE_REQUEST_PIPELINE GIT_PUSH_EVENT])
        expect(profile.reload.scan_profile_triggers.map(&:trigger_type))
          .to match_array(%w[merge_request_pipeline git_push_event])
        expect(profile.configurations.count).to eq(1)
      end
    end
  end
end
