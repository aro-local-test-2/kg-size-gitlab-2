# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Versions::BackfillFromArtifactSourceService, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:service) { create(:cd_service, application: application, organization: organization) }
  let_it_be(:project) { create(:project, organization: organization) }

  let_it_be_with_reload(:container_repository) { create(:container_repository, project: project, name: 'web') }

  let(:source_ref) { "#{::Gitlab.config.registry.host_port}/#{container_repository.path}" }
  let(:artifact_source) do
    create(:cd_artifact_source, service: service, organization: organization, source_ref: source_ref)
  end

  subject(:execute) { described_class.new(artifact_source).execute }

  before do
    allow(::ContainerRepository).to receive(:find_by_path)
      .with(satisfy { |path| path.to_s == container_repository.path })
      .and_return(container_repository)
  end

  def stub_gitlab_api_support(supported:)
    allow(container_repository).to receive(:gitlab_api_client)
      .and_return(instance_double(ContainerRegistry::GitlabApiClient, supports_gitlab_api?: supported))
  end

  def stub_tags(tags)
    stub_gitlab_api_support(supported: true)
    allow(container_repository).to receive(:tags_page).with(sort: '-published_at', page_size: 3)
      .and_return(tags: tags)
  end

  def tag_double(name, digest)
    instance_double(ContainerRegistry::Tag, name: name, digest: digest)
  end

  describe '#execute' do
    context 'when the source_ref resolves to a GitLab-hosted repository' do
      before do
        stub_tags([tag_double('v3', 'sha256:3'), tag_double('v2', 'sha256:2'), tag_double('v1', 'sha256:1')])
      end

      it 'creates a version for each of the latest tags, keeping the host-prefixed reference' do
        expect { execute }.to change { artifact_source.versions.count }.by(3)

        expect(artifact_source.versions.pluck(:name, :digest, :reference)).to contain_exactly(
          ['v3', 'sha256:3', "#{source_ref}:v3"],
          ['v2', 'sha256:2', "#{source_ref}:v2"],
          ['v1', 'sha256:1', "#{source_ref}:v1"]
        )
      end

      it 'returns the created versions in the payload' do
        response = execute

        expect(response).to be_success
        expect(response.payload[:versions].map(&:name)).to contain_exactly('v1', 'v2', 'v3')
      end
    end

    context 'when the registry has no tags yet' do
      before do
        stub_tags([])
      end

      it 'succeeds without creating any versions' do
        expect { execute }.not_to change { Cd::Version.count }
        expect(execute).to be_success
      end
    end

    context 'when the registry does not support the GitLab API' do
      before do
        stub_gitlab_api_support(supported: false)
      end

      it 'succeeds without creating any versions' do
        expect { execute }.not_to change { Cd::Version.count }
        expect(execute).to be_success
      end
    end

    context 'when the resolved repository belongs to a different organization' do
      before do
        other_project = create(:project)
        allow(container_repository).to receive(:project).and_return(other_project)
        stub_gitlab_api_support(supported: true)
      end

      it 'succeeds without creating any versions' do
        expect { execute }.not_to change { Cd::Version.count }
        expect(execute).to be_success
      end
    end

    context 'when source_ref does not resolve to a known repository' do
      before do
        allow(::ContainerRepository).to receive(:find_by_path).and_return(nil)
      end

      it 'succeeds without creating any versions' do
        expect { execute }.not_to change { Cd::Version.count }
        expect(execute).to be_success
      end
    end

    context 'when the registry request fails' do
      before do
        stub_gitlab_api_support(supported: true)
        allow(container_repository).to receive(:tags_page).and_raise(Faraday::ConnectionFailed, 'boom')
      end

      it 'returns an error and creates no versions' do
        expect { execute }.not_to change { Cd::Version.count }

        response = execute
        expect(response).to be_error
        expect(response.reason).to eq(:registry_unavailable)
      end
    end
  end
end
