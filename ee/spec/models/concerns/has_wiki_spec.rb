# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HasWiki, feature_category: :wiki do
  describe '#check_wiki_path_conflict' do
    context 'when validating a subgroup' do
      let_it_be(:parent_group) { create(:group) }

      it 'flags a conflict with a sibling group with the .wiki shadow path', :aggregate_failures do
        create(:group, parent: parent_group, path: 'foo.wiki')
        group = build(:group, parent: parent_group, path: 'foo')

        expect(group).not_to be_valid
        expect(group.errors[:name]).to include('has already been taken')
      end

      it 'flags a conflict with a sibling project with the .wiki shadow path', :aggregate_failures do
        create(:project, namespace: parent_group, path: 'foo.wiki')
        group = build(:group, parent: parent_group, path: 'foo')

        expect(group).not_to be_valid
        expect(group.errors[:name]).to include('has already been taken')
      end

      it 'does not flag a conflict with a group under a different parent' do
        other_parent = create(:group)
        create(:group, parent: other_parent, path: 'foo.wiki')
        group = build(:group, parent: parent_group, path: 'foo')

        expect(group).to be_valid
      end

      it 'does not flag a conflict with a project under a different namespace' do
        other_parent = create(:group)
        create(:project, namespace: other_parent, path: 'foo.wiki')
        group = build(:group, parent: parent_group, path: 'foo')

        expect(group).to be_valid
      end
    end

    context 'when validating a root-level group' do
      it 'flags a true root-level sibling conflict with another root group', :aggregate_failures do
        create(:group, parent: nil, path: 'foo.wiki')
        group = build(:group, parent: nil, path: 'foo')

        expect(group).not_to be_valid
        expect(group.errors[:name]).to include('has already been taken')
      end

      # Reproduces https://gitlab.com/gitlab-org/gitlab/-/work_items/599240.
      # A group named "foo.wiki" nested under an unrelated parent must not
      # cause a conflict for a root-level group named "foo".
      it 'does not flag a conflict when the matching group lives under an unrelated parent' do
        unrelated_parent = create(:group)
        create(:group, parent: unrelated_parent, path: 'foo.wiki')
        group = build(:group, parent: nil, path: 'foo')

        expect(group).to be_valid
      end

      # Symmetric under-detection: GroupsFinder is called with current_user: nil,
      # which only sees publicly-visible groups. A private sibling at the same
      # level should still produce a conflict.
      it 'flags a conflict even when the sibling root group is private', :aggregate_failures do
        create(:group, :private, parent: nil, path: 'foo.wiki')
        group = build(:group, parent: nil, path: 'foo')

        expect(group).not_to be_valid
        expect(group.errors[:name]).to include('has already been taken')
      end
    end
  end
end
