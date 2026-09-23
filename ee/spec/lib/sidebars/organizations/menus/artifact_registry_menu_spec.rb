# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidebars::Organizations::Menus::ArtifactRegistryMenu, feature_category: :artifact_registry do
  # rubocop:disable RSpec/FactoryBot/AvoidCreate -- read_artifact_registry policy checks organization membership, which requires persisted records
  let_it_be(:organization) { create(:organization) }
  let_it_be(:member) { create(:user) }
  let_it_be(:owner) { create(:user) }

  let(:user) { member }
  let(:context) { Sidebars::Context.new(current_user: user, container: organization) }
  let(:mapping) { nil }
  let(:resolved) { nil }

  subject(:menu) { described_class.new(context) }

  before_all do
    create(:organization_user, organization: organization, user: member)
    create(:organization_owner, organization: organization, user: owner)
  end

  before do
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
    allow(mapping).to receive(:registry).and_return(resolved) if mapping
  end

  def registry(status:, slug: 'my-registry')
    ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: status, created_at: nil)
  end

  shared_examples 'a hidden menu' do
    it 'renders nothing' do
      expect(menu.render?).to be false
    end
  end

  shared_examples 'a single link to the setup page' do
    it 'renders one link and does not expand to Repositories', :aggregate_failures do
      expect(menu.render?).to be true
      expect(menu.renderable_items).to be_empty
      expect(menu.link).to eq("/o/#{organization.path}/-/artifact_registry")
      expect(menu.active_routes).to eq(page: "/o/#{organization.path}/-/artifact_registry")
    end
  end

  shared_examples 'an area expanding to Repositories' do
    it 'expands to a Repositories item on the resolved handle', :aggregate_failures do
      expect(menu.render?).to be true
      expect(menu.renderable_items.size).to eq(1)

      item = menu.renderable_items.first
      path = "/o/#{organization.path}/-/artifact_registry/my-registry/repositories"

      expect(item.title).to eq('Repositories')
      expect(item.link).to eq(path)
      expect(item.active_routes).to eq(controller: 'organizations/artifact_registry_repositories')
      expect(menu.link).to eq(path)
      expect(menu.active_routes).to eq({})
    end
  end

  describe 'the state table' do
    context 'with no mapping row' do
      context 'when the viewer holds the update ability' do
        let(:user) { owner }

        it_behaves_like 'a single link to the setup page'
      end

      context 'when the viewer holds only the read ability' do
        it_behaves_like 'a hidden menu'
      end
    end

    context 'with a mapping row' do
      let(:mapping) { build_stubbed(:artifact_registry_namespace_mapping, organization: organization) }

      context 'when the handle resolves' do
        %w[active suspended disabled blocked something-unrecognized].each do |status|
          context "when the status is #{status}" do
            let(:resolved) { registry(status: status) }

            it_behaves_like 'an area expanding to Repositories'
          end
        end

        context 'when the viewer holds the update ability' do
          let(:user) { owner }
          let(:resolved) { registry(status: 'active') }

          it_behaves_like 'an area expanding to Repositories'
        end
      end

      context 'when the status is unknown, which carries no handle' do
        let(:resolved) do
          registry(status: ArtifactRegistry::NamespaceMapping::UNKNOWN_STATUS, slug: nil)
        end

        it_behaves_like 'a hidden menu'
      end

      context 'when the resolution failed' do
        let(:resolved) { ArtifactRegistry::NamespaceMapping::ResolutionFailure.new(error_class: 'x') }

        it_behaves_like 'a hidden menu'
      end

      context 'when the resolution failed for a viewer holding the update ability' do
        let(:user) { owner }
        let(:resolved) { ArtifactRegistry::NamespaceMapping::ResolutionFailure.new(error_class: 'x') }

        it_behaves_like 'a hidden menu'
      end
    end
  end

  describe 'resolution ordering' do
    let(:mapping) { build_stubbed(:artifact_registry_namespace_mapping, organization: organization) }
    let(:resolved) { registry(status: 'active') }

    shared_examples 'a gate that resolves nothing' do
      it 'hides the area without resolving against Artifact Registry', :aggregate_failures do
        expect(mapping).not_to receive(:registry)

        expect(menu.render?).to be false
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(artifact_registry_ui: false)
      end

      it_behaves_like 'a gate that resolves nothing'
    end

    context 'when the viewer cannot read the artifact registry' do
      let(:user) { create(:user) }

      it_behaves_like 'a gate that resolves nothing'
    end

    context 'when there is no current user' do
      let(:user) { nil }

      it_behaves_like 'a gate that resolves nothing'
    end

    it_behaves_like 'a surface gated on a configured Artifact Registry base URL', 'a gate that resolves nothing'
  end

  describe '#title' do
    it 'is the Artifact registry navigation area title' do
      expect(menu.title).to eq(s_('ArtifactRegistry|Artifact registry'))
    end
  end

  describe '#sprite_icon' do
    it 'has an icon' do
      expect(menu.sprite_icon).to be_present
    end
  end

  describe '#pick_into_super_sidebar?' do
    it { expect(menu.pick_into_super_sidebar?).to be true }
  end
end
# rubocop:enable RSpec/FactoryBot/AvoidCreate
