# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfilePermissions, feature_category: :security_testing_configuration do
  include GraphqlHelpers

  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }

  let_it_be(:root_maintainer) { create(:user, maintainer_of: root_group) }
  let_it_be(:subgroup_maintainer) { create(:user, maintainer_of: subgroup) }
  let_it_be(:non_member) { create(:user) }

  let(:permission_type) { ::Types::PermissionTypes::Group }
  let(:root_scoped_abilities) { described_class::ROOT_SCOPED_ABILITIES }
  let(:object_scoped_abilities) { %i[apply_security_scan_profiles] }
  let(:all_abilities) { root_scoped_abilities + object_scoped_abilities }

  def resolve_abilities(abilities)
    abilities.index_with do |ability|
      resolve_field(ability, object, current_user: current_user, object_type: permission_type)
    end
  end

  before do
    stub_licensed_features(security_scan_profiles: true)
  end

  it 'exposes every scan profile ability' do
    all_abilities.each do |ability|
      expect(permission_type).to have_graphql_field(ability)
    end
  end

  context 'when queried on a subgroup' do
    let(:object) { subgroup }

    context 'when the user is a maintainer of the root group' do
      let(:current_user) { root_maintainer }

      it 'grants every ability' do
        expect(resolve_abilities(all_abilities).values).to all(be(true))
      end
    end

    context 'when the user is a maintainer of the subgroup only' do
      let(:current_user) { subgroup_maintainer }

      it 'denies the root-scoped abilities, because scan profiles belong to the root ancestor' do
        expect(resolve_abilities(root_scoped_abilities).values).to all(be(false))
      end

      it 'grants apply, because attaching a profile is authorized per project' do
        expect(resolve_abilities(object_scoped_abilities).values).to all(be(true))
      end
    end

    context 'when the user is not a member' do
      let(:current_user) { non_member }

      it 'denies every ability' do
        expect(resolve_abilities(all_abilities).values).to all(be(false))
      end
    end

    context 'when unauthenticated' do
      let(:current_user) { nil }

      it 'denies every ability' do
        expect(resolve_abilities(all_abilities).values).to all(be(false))
      end
    end

    context 'when the licensed feature is unavailable' do
      let(:current_user) { root_maintainer }

      before do
        stub_licensed_features(security_scan_profiles: false)
      end

      it 'denies every ability' do
        expect(resolve_abilities(all_abilities).values).to all(be(false))
      end
    end
  end

  context 'when queried on the root group itself' do
    let(:object) { root_group }
    let(:current_user) { root_maintainer }

    it 'grants every ability' do
      expect(resolve_abilities(all_abilities).values).to all(be(true))
    end
  end

  context 'when the resource has no root ancestor' do
    let(:object) { build(:group, parent: nil).tap { |group| allow(group).to receive(:root_ancestor).and_return(nil) } }
    let(:current_user) { root_maintainer }

    it 'denies the root-scoped abilities instead of raising' do
      expect(resolve_abilities(root_scoped_abilities).values).to all(be(false))
    end
  end
end
