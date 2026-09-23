# frozen_string_literal: true

require 'spec_helper'

RSpec.shared_examples 'it attempts to associate the profile' do |dast_profile_name_key|
  let(:association) { dast_build.public_send(profile.class.underscore.to_sym) }
  let(:profile_name) { public_send(dast_profile_name_key) }

  context 'when the profile exists' do
    it 'assigns the association' do
      expect(association).to eq(profile)
    end
  end

  shared_examples 'it has no effect' do
    it 'does not assign the association' do
      expect(association).to be_nil
    end
  end

  context 'when the profile is not provided' do
    let(dast_profile_name_key) { nil }
    let(:dast_build) do
      create_dast_build(site_profile_name: dast_site_profile_name, scanner_profile_name: dast_scanner_profile_name)
    end

    it_behaves_like 'it has no effect'
  end

  context 'when the profile does not exist' do
    let(dast_profile_name_key) { SecureRandom.hex }
    let(:dast_build) do
      create_dast_build(site_profile_name: dast_site_profile_name, scanner_profile_name: dast_scanner_profile_name)
    end

    it_behaves_like 'an error occurred during the dast profile association' do
      let(:error_message) { "DAST profile not found: #{profile_name}" }
    end
  end
end

RSpec.shared_examples 'an error occurred during the dast profile association' do
  it_behaves_like 'an error occurred'
end

RSpec.describe AppSec::Dast::Profiles::CreateAssociationsService do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:outsider) { create(:user) }
  let_it_be(:dast_site_profile) { create(:dast_site_profile, project: project) }
  let_it_be(:dast_scanner_profile) { create(:dast_scanner_profile, project: project) }

  let(:dast_site_profile_name) { dast_site_profile.name }
  let(:dast_scanner_profile_name) { dast_scanner_profile.name }

  let_it_be(:pipeline) { create(:ci_pipeline, project: project, user: user) }
  let_it_be(:stage) { create(:ci_stage, project: project, pipeline: pipeline, name: :dast) }

  let_it_be_with_reload(:dast_build) do
    create_dast_build(site_profile_name: dast_site_profile.name, scanner_profile_name: dast_scanner_profile.name)
  end

  let(:params) { { builds: [dast_build] } }

  subject { described_class.new(project: project, current_user: user, params: params).execute }

  def create_dast_build(site_profile_name:, scanner_profile_name:)
    create(
      :ci_build,
      project: project,
      user: user,
      pipeline: pipeline,
      ci_stage: stage,
      options: {
        dast_configuration: {
          site_profile: site_profile_name,
          scanner_profile: scanner_profile_name
        }
      }
    )
  end

  describe '#execute' do
    context 'when the feature is licensed' do
      before do
        stub_licensed_features(security_on_demand_scans: true)
        subject
      end

      context 'when the user cannot create dast scans' do
        let_it_be(:user) { outsider }

        it_behaves_like 'an error occurred during the dast profile association' do
          let(:error_message) { 'Insufficient permissions for dast_configuration keyword' }
        end
      end

      context 'dast_site_profile' do
        let(:profile) { dast_site_profile }

        it_behaves_like 'it attempts to associate the profile', :dast_site_profile_name
      end

      context 'dast_scanner_profile' do
        let(:profile) { dast_scanner_profile }

        it_behaves_like 'it attempts to associate the profile', :dast_scanner_profile_name
      end

      context 'when the build has multiple dast_configurations' do
        let(:dast_site_profile_2) do
          create(:dast_site_profile, project: custom_project, name: dast_site_profile_2_name)
        end

        let(:dast_scanner_profile_2) do
          create(:dast_scanner_profile, project: custom_project, name: dast_scanner_profile_2_name)
        end

        let!(:dast_build_2) do
          create_dast_build(
            site_profile_name: dast_site_profile_2.name,
            scanner_profile_name: dast_scanner_profile_2.name
          )
        end

        let(:builds) { [dast_build, dast_build_2] }
        let(:params) { { builds: builds } }

        context 'with different name and same project' do
          let(:dast_scanner_profile_2_name) { 'test' }
          let(:dast_site_profile_2_name) { 'test' }
          let(:custom_project) { project }
          let(:expected_associations) do
            {
              dast_build => {
                dast_site_profile: dast_site_profile,
                dast_scanner_profile: dast_scanner_profile
              },
              dast_build_2 => {
                dast_site_profile: dast_site_profile_2,
                dast_scanner_profile: dast_scanner_profile_2
              }
            }
          end

          it 'associate the associations correctly', :aggregate_failures do
            expected_associations.each do |build, associations|
              associations.each do |association_name, association|
                expect(build.public_send(association_name)).to eq(association)
              end
            end
          end
        end

        context 'with same named profiles from different project' do
          let(:dast_scanner_profile_2_name) { dast_scanner_profile.name }
          let(:dast_site_profile_2_name) { dast_site_profile.name }
          let(:custom_project) { create(:project, namespace: project.namespace) }
          let(:expected_associations) do
            {
              dast_build => {
                dast_site_profile: dast_site_profile,
                dast_scanner_profile: dast_scanner_profile
              }
            }
          end

          it 'associate the associations correctly', :aggregate_failures do
            expected_associations.each do |build, associations|
              associations.each do |association_name, association|
                expect(build.public_send(association_name)).to eq(association)
              end
            end
          end
        end
      end
    end

    context 'when not licensed' do
      before do
        stub_licensed_features(security_on_demand_scans: false)
      end

      let(:error_message) { 'Insufficient permissions for dast_configuration keyword' }

      it_behaves_like 'an error occurred during the dast profile association' do
        let(:error_message) { 'Insufficient permissions for dast_configuration keyword' }
      end
    end
  end
end
