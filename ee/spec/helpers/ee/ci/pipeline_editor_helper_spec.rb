# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::Ci::PipelineEditorHelper, feature_category: :pipeline_composition do
  let_it_be(:project) { create(:project, :public) }
  let_it_be(:user) { create(:user) }

  describe '#js_pipeline_editor_data' do
    before do
      allow(helper).to receive_messages(
        namespace_project_new_merge_request_path: '/mock/project/-/merge_requests/new',
        image_path: 'foo',
        current_user: user
      )

      stub_all_feature_flags
    end

    subject(:pipeline_editor_data) { helper.js_pipeline_editor_data(project) }

    shared_examples 'no licensed features keys' do
      it 'returns dataset with no licensed features keys' do
        expect(pipeline_editor_data.keys).not_to include('api-fuzzing-configuration-path')
        expect(pipeline_editor_data.keys).not_to include('dast-configuration-path')
        expect(pipeline_editor_data.keys).not_to include('ai_chat_available')
      end
    end

    shared_examples 'api fuzzing only' do
      it 'includes keys for only api fuzzing' do
        expect(pipeline_editor_data.keys).to include('api-fuzzing-configuration-path')
        expect(pipeline_editor_data.keys).to include('dast-configuration-path')
        expect(pipeline_editor_data.keys).not_to include('ai_chat_available')
      end
    end

    context 'with api_fuzzing enabled' do
      before do
        stub_licensed_features(api_fuzzing: true)
      end

      it_behaves_like 'api fuzzing only'
    end

    context 'with ai ci config chat and api_fuzzing enabled' do
      before do
        stub_licensed_features(api_fuzzing: true)
      end

      context 'when user can create a pipeline' do
        before do
          project.add_developer(user)
        end

        it 'includes keys for all features' do
          expect(pipeline_editor_data.keys).to include('api-fuzzing-configuration-path')
          expect(pipeline_editor_data.keys).to include('dast-configuration-path')
        end
      end

      context 'when user cannot create a pipeline' do
        it_behaves_like 'api fuzzing only'
      end
    end

    context 'without features licensed and enabled' do
      context 'when user can create a pipeline' do
        before do
          project.add_developer(user)
        end

        it_behaves_like 'no licensed features keys'
      end

      context 'when user cannot create a pipeline' do
        it_behaves_like 'no licensed features keys'
      end
    end

    context 'with identity verification' do
      using RSpec::Parameterized::TableSyntax

      where(:authorized, :expected) do
        true  | 'false'
        false | 'true'
      end

      with_them do
        before do
          allow_next_instance_of(::Users::IdentityVerification::AuthorizeCi) do |instance|
            allow(instance).to receive(:user_can_run_jobs?).and_return(authorized)
          end
        end

        it 'sets identity-verification-required based on job authorization' do
          expect(pipeline_editor_data['identity-verification-required']).to eq(expected)
        end
      end

      context 'when current_user is nil' do
        before do
          allow(helper).to receive(:current_user).and_return(nil)
        end

        it 'sets identity-verification-required to false without checking authorization' do
          expect(pipeline_editor_data['identity-verification-required']).to eq('false')
        end
      end

      it 'includes identity-verification-path' do
        expect(pipeline_editor_data['identity-verification-path']).to eq(identity_verification_path)
      end
    end
  end
end
