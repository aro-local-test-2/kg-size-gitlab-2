# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Components::FetchService, feature_category: :pipeline_composition do
  include_context 'with pipeline policy context'

  let_it_be(:root_group) { create(:group) }
  let_it_be(:requesting_project) { create(:project, group: root_group) }
  let_it_be(:requesting_project_policy_project) { create(:project, :small_repo, group: root_group) }

  let_it_be(:requesting_project_policy_configuration) do
    create(:security_orchestration_policy_configuration,
      project: requesting_project,
      security_policy_management_project: requesting_project_policy_project)
  end

  let_it_be(:requesting_project_pep_policy) do
    create(:security_policy, :pipeline_execution_policy,
      security_orchestration_policy_configuration: requesting_project_policy_configuration,
      linked_projects: [requesting_project])
  end

  let_it_be(:bot_user) { create(:user, :security_policy_bot) }
  let_it_be(:current_host) { Gitlab.config.gitlab.host }
  let_it_be(:content) do
    <<~COMPONENT
    job:
      script: echo
    COMPONENT
  end

  let(:creating_policy_pipeline) { true }
  let(:project) { requesting_project }
  let(:current_user) { bot_user }

  let(:service) do
    described_class.new(
      address: address,
      current_user: current_user,
      requesting_project: requesting_project,
      pipeline_policy_context: pipeline_policy_context
    )
  end

  describe '#execute', :aggregate_failures do
    subject(:result) { service.execute }

    describe 'pipeline_execution_policy_component_access_allowed?' do
      let_it_be_with_reload(:target_project) do
        project = create(
          :project, :custom_repo, :internal,
          group: root_group,
          files: {
            'templates/policy-component.yml' => content,
            'templates/nested/template.yml' => content
          }
        )

        project.repository.add_tag(project.creator, '1.0.0', project.repository.commit.sha)
        project
      end

      let(:address) { "#{current_host}/#{target_project.full_path}/policy-component@1.0.0" }

      shared_examples 'user has no access to the component' do
        it 'is an error and includes an access denied message', :aggregate_failures do
          expect(result).to be_error
          expect(result.reason).to eq(:not_allowed)
          expect(result.message).to include('Internal')
        end
      end

      shared_examples 'user has access to the component' do
        it 'returns the component content successfully' do
          expect(result).to be_success
          expect(result.payload[:content]).to eq(content)
        end
      end

      context 'when policy file access is not enabled' do
        it_behaves_like 'user has no access to the component'
      end

      context 'when policy file access is explicitly disabled' do
        before do
          target_project.project_setting.update!(
            pipeline_execution_policy_bot_access_enabled: false
          )
        end

        it_behaves_like 'user has no access to the component'
      end

      context 'when policy file access is enabled' do
        before do
          target_project.project_setting.update!(
            pipeline_execution_policy_bot_access_enabled: true,
            pipeline_execution_policy_bot_access_file_patterns: ['templates/**/*.yml']
          )
        end

        context 'with security policy bot user' do
          it_behaves_like 'user has access to the component'
        end

        context 'when validating multiple component fetches in the same request', :request_store do
          let(:additional_service) do
            described_class.new(
              address: address,
              current_user: current_user,
              requesting_project: requesting_project,
              pipeline_policy_context: pipeline_policy_context
            )
          end

          it 'caches access checks in SafeRequestStore' do
            expect(result).to be_success
            expect(additional_service.execute).to be_success

            simple_cache_key = [
              'Ci::Components::FetchService',
              'pipeline_execution_policy_component_access_allowed',
              target_project.id,
              requesting_project.id,
              'templates/policy-component.yml'
            ]
            complex_cache_key = [
              'Ci::Components::FetchService',
              'pipeline_execution_policy_component_access_allowed',
              target_project.id,
              requesting_project.id,
              'templates/policy-component/template.yml'
            ]
            expect(Gitlab::SafeRequestStore.exist?(simple_cache_key) ||
              Gitlab::SafeRequestStore.exist?(complex_cache_key)).to be(true)
          end
        end

        context 'when requesting_project parameter is nil' do
          let(:service) do
            described_class.new(
              address: address,
              current_user: current_user,
              requesting_project: nil,
              pipeline_policy_context: pipeline_policy_context
            )
          end

          it 'uses target_project from pipeline_policy_context' do
            expect(result).to be_success
            expect(result.payload[:content]).to eq(content)
          end
        end

        context 'when both requesting_project and pipeline_policy_context are nil' do
          let(:service) do
            described_class.new(
              address: address,
              current_user: current_user,
              requesting_project: nil,
              pipeline_policy_context: nil
            )
          end

          it_behaves_like 'user has no access to the component'
        end

        context 'when file pattern does not match component path' do
          before do
            target_project.project_setting.update!(
              pipeline_execution_policy_bot_access_file_patterns: ['other/**/*.yml']
            )
          end

          it_behaves_like 'user has no access to the component'
        end

        context 'when target project is outside allowed group hierarchy' do
          let(:other_group) { build_stubbed(:group) }
          let(:outside_project) { build_stubbed(:project, group: other_group) }

          before do
            allow(pipeline_policy_context.pipeline_execution_context)
              .to receive(:target_project).and_return(outside_project)
          end

          it_behaves_like 'user has no access to the component'
        end

        context 'when creating_policy_pipeline? is false' do
          let(:creating_policy_pipeline) { false }

          it_behaves_like 'user has no access to the component'
        end

        context 'when pipeline_execution_context.target_project is nil' do
          before do
            allow(pipeline_policy_context.pipeline_execution_context).to receive(:target_project).and_return(nil)
          end

          it 'falls back to requesting_project for access check' do
            expect(result).to be_success
            expect(result.payload[:content]).to eq(content)
          end
        end

        context 'with complex component path (nested directory)' do
          let(:address) { "#{current_host}/#{target_project.full_path}/nested@1.0.0" }

          before do
            target_project.project_setting.update!(
              pipeline_execution_policy_bot_access_file_patterns: ['templates/nested/*.yml']
            )
          end

          it_behaves_like 'user has access to the component'
        end
      end
    end
  end
end
