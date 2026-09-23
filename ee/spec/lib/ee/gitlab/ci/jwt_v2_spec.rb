# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::JwtV2, feature_category: :secrets_management do
  let(:namespace) { build_stubbed(:namespace) }
  let(:project) { build_stubbed(:project, namespace: namespace) }
  let(:user) do
    build_stubbed(
      :user,
      identities: [build_stubbed(:identity, extern_uid: '1', provider: 'github')]
    )
  end

  let(:pipeline) { build_stubbed(:ci_pipeline, ref: 'auto-deploy-2020-03-19') }
  let(:runner) { build_stubbed(:ci_runner) }
  let(:aud) { nil }
  let(:sub_components) { [:project_path, :ref_type, :ref] }
  let(:target_audience) { nil }
  let(:options) { nil }

  let(:build) do
    build_stubbed(
      :ci_build,
      project: project,
      user: user,
      pipeline: pipeline,
      runner: runner,
      options: options
    )
  end

  subject(:ci_job_jwt_v2) do
    described_class.new(build, ttl: 30, aud: aud, sub_components: sub_components, target_audience: target_audience)
  end

  describe '#payload' do
    subject(:payload) { ci_job_jwt_v2.payload }

    describe 'job_config' do
      shared_examples_for 'does not include job_config in the payload' do
        it 'does not include job_config in the payload' do
          expect(payload).not_to include(:job_config)
        end
      end

      context 'without options' do
        it_behaves_like 'does not include job_config in the payload'
      end

      context 'with options but without policy option' do
        let(:options) { { job_timeout: 30 } }

        it_behaves_like 'does not include job_config in the payload'
      end

      context 'with policy options' do
        let_it_be_with_refind(:policy_project) { create(:project, :small_repo) }
        let(:config_sha) { 'abc123def456' }

        context 'with all necessary options' do
          let(:options) { { policy: { project_id: policy_project.id, sha: config_sha } } }

          it 'contains job_config' do
            expected_url = "http://localhost/#{policy_project.full_path}/-/blob/#{config_sha}/.gitlab/security-policies/policy.yml"

            expect(payload[:job_config]).to eq({
              url: expected_url,
              sha: config_sha
            })
          end

          context 'when project does not exist' do
            let(:options) { { policy: { project_id: non_existing_record_id, sha: config_sha } } }

            it_behaves_like 'does not include job_config in the payload'

            it 'logs a warning' do
              expect(Gitlab::AppLogger).to receive(:warn).with(
                hash_including(
                  message: 'Policy project not found when generating JWT claims',
                  project_id: non_existing_record_id
                )
              )

              payload
            end
          end
        end

        context 'when sha option is empty' do
          let(:options) { { policy: { project_id: policy_project.id } } }

          it_behaves_like 'does not include job_config in the payload'
        end

        context 'when project_id option is empty' do
          let(:options) { { policy: { sha: config_sha } } }

          it_behaves_like 'does not include job_config in the payload'
        end

        context 'when neither sha nor project_id is provided' do
          let(:options) { { policy: {} } }

          it_behaves_like 'does not include job_config in the payload'
        end
      end
    end
  end
end

RSpec.describe Gitlab::Ci::JwtV2, 'block_jwt_for_reclaimed_paths on SaaS',
  :saas_gitlab_com_subscriptions, feature_category: :secrets_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project, user: user) }
  let_it_be(:build) { create(:ci_build, project: project, user: user, pipeline: pipeline) }

  let(:sub_components) { [:project_path, :ref_type, :ref] }

  subject(:mint) do
    described_class.new(build, ttl: 30, aud: nil, sub_components: sub_components, target_audience: nil).encoded
  end

  context 'when a tombstone exists for the project path owned by a different project' do
    before do
      create(:burned_project_route,
        organization: project.organization, path: project.full_path, project_id: project.id + 1)

      stub_env('IN_MEMORY_APPLICATION_SETTINGS', 'false')
      setting = ApplicationSetting.current || create(:application_setting)
      setting.update_column(:ci_cd_settings,
        setting.ci_cd_settings.merge('block_jwt_for_reclaimed_paths' => false))
      Gitlab::CurrentSettings.expire_current_application_settings
    end

    context 'when sub_components includes project_path' do
      it 'raises OidcBurnedPathError despite the stored false' do
        expect(ApplicationSetting.current.ci_cd_settings['block_jwt_for_reclaimed_paths']).to be(false)
        expect { mint }.to raise_error(Gitlab::Ci::OidcBurnedPathError)
      end
    end
  end
end
