# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Versions::CreateService, feature_category: :continuous_delivery do
  let_it_be(:artifact_source) { create(:cd_artifact_source) }
  let_it_be(:current_user) { create(:user) }

  let(:params) { { name: 'external-2026.08.19+build.7' } }

  subject(:result) do
    described_class.new(artifact_source: artifact_source, current_user: current_user, params: params).execute
  end

  describe '#execute' do
    it 'creates an unverified version with the given free-text name', :aggregate_failures do
      expect { result }.to change { ::Cd::Version.count }.by(1)

      version = result.payload[:version]
      expect(result).to be_success
      expect(version).to have_attributes(
        artifact_source: artifact_source,
        name: 'external-2026.08.19+build.7',
        verified: false
      )
    end

    context 'when verified is explicitly set to true' do
      let(:params) { { name: 'v1.2.3', verified: true } }

      it 'creates a verified version' do
        expect(result).to be_success
        expect(result.payload[:version]).to have_attributes(name: 'v1.2.3', verified: true)
      end
    end

    context 'when the name is blank' do
      let(:params) { { name: '' } }

      it 'does not create a version and returns the error' do
        expect { result }.not_to change { ::Cd::Version.count }
        expect(result).to be_error
        expect(result.message).to include("Name can't be blank")
      end
    end

    context 'when a version with the same name already exists for the artifact source' do
      before do
        create(:cd_version, :unverified, artifact_source: artifact_source, name: 'external-2026.08.19+build.7')
      end

      it 'does not create a version and returns the error' do
        expect { result }.not_to change { ::Cd::Version.count }
        expect(result).to be_error
        expect(result.message).to include('Name has already been taken')
      end
    end
  end
end
