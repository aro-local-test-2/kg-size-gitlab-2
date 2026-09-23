# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidebars::Organizations::Menus::SettingsMenu, feature_category: :navigation do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:member) { create(:user) }
  let_it_be(:non_member) { create(:user) }

  let(:user) { owner }
  let(:container) { organization }
  let(:context) { Sidebars::Context.new(current_user: user, container: container) }
  let(:menu) { described_class.new(context) }

  subject(:artifact_registry_item) do
    menu.renderable_items.find { |item| item.item_id == :organization_settings_artifact_registry }
  end

  before_all do
    create(:organization_user, :owner, organization: organization, user: owner)
    create(:organization_user, organization: organization, user: member)
    create(:artifact_registry_namespace_mapping, organization: organization)
  end

  describe 'the Artifact registry settings item' do
    shared_examples 'a hidden menu item' do
      it 'does not insert the item' do
        expect(artifact_registry_item).to be_nil
      end
    end

    context 'when the organization is activated and the user is an owner' do
      it 'inserts the item linking to the organization settings artifact registry path', :aggregate_failures do
        expect(artifact_registry_item).to be_present
        expect(artifact_registry_item.link)
          .to eq(Gitlab::Routing.url_helpers.artifact_registry_settings_organization_path(organization))
      end
    end

    context 'when the artifact_registry_ui feature flag is disabled' do
      before do
        stub_feature_flags(artifact_registry_ui: false)
      end

      it_behaves_like 'a hidden menu item'
    end

    it_behaves_like 'a surface gated on a configured Artifact Registry base URL', 'a hidden menu item'

    context 'when the user is not a member' do
      let(:user) { non_member }

      it_behaves_like 'a hidden menu item'
    end

    context 'when the user is a member without the update ability' do
      let(:user) { member }

      it_behaves_like 'a hidden menu item'

      it 'does not render the menu' do
        expect(menu.render?).to be(false)
      end
    end

    context 'when the handle does not resolve' do
      let(:mapping) { organization.artifact_registry_namespace_mapping }

      before do
        allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
        allow(mapping).to receive(:registry)
          .and_return(ArtifactRegistry::NamespaceMapping::ResolutionFailure.new(error_class: 'x'))
      end

      it 'still inserts the item, deciding on the mapping row alone', :aggregate_failures do
        expect(artifact_registry_item).to be_present
        expect(mapping).not_to have_received(:registry)
      end
    end

    context 'when the organization has no artifact registry namespace mapping' do
      let_it_be(:unactivated_organization) { create(:organization, owners: owner) }

      let(:container) { unactivated_organization }

      it_behaves_like 'a hidden menu item'
    end
  end
end
