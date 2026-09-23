# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::ProjectAuthorizations, feature_category: :system_access do
  def map_access_levels(rows)
    rows.each_with_object({}) do |row, hash|
      hash[row.project_id] = row.access_level
    end
  end

  context 'when a group is shared at MINIMAL_ACCESS level' do
    let_it_be(:shared_with_group) { create(:group) }
    let_it_be(:shared_group) { create(:group) }
    let_it_be(:shared_group_project) { create(:project, namespace: shared_group) }
    let_it_be(:user) { create(:user) }

    let(:service) { described_class.new(user) }
    let(:authorizations) { service.calculate }

    subject(:mapping) { map_access_levels(authorizations) }

    before_all do
      shared_with_group.add_developer(user)
    end

    before do
      # The link is created here rather than in before_all because the MINIMAL_ACCESS
      # validation needs the license stub, which is only active within an example.
      stub_licensed_features(minimal_access_role: true)

      # Share shared_group with shared_with_group at Minimal Access (5).
      # LEAST(developer=30, minimal_access=5) = 5 must not produce a project_authorization row.
      create(:group_group_link, shared_group: shared_group, shared_with_group: shared_with_group,
        group_access: Gitlab::Access::MINIMAL_ACCESS)
    end

    it 'does not insert any project_authorization row for members inheriting access solely through that share' do
      expect(mapping[shared_group_project.id]).to be_nil
    end
  end
end
