# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'NotesHelpers' do
  describe '#find_noteable' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group, :public, owners: user) }
    let_it_be(:other_group) { create(:group, :public) }
    let_it_be(:epic) { create(:epic, author: user, group: group) }
    let!(:parent_id) { group.id }
    let(:noteable_type) { Epic }

    let(:klazz) do
      klazz = Class.new do
        def initialize(user)
          @user = user
        end

        def current_user
          @user
        end

        def can?(user, ability, noteable)
          user == @user && ability == :read_epic
        end
      end

      klazz.prepend(API::Helpers::NotesHelpers)
    end

    subject(:notes_helper) { klazz.new(user) }

    before do
      stub_licensed_features(epics: true)
    end

    describe '#find_noteable' do
      it 'returns the expected epic' do
        allow(notes_helper).to receive(:user_group).and_return(group)

        expect(notes_helper.find_noteable(noteable_type, epic.id)).to eq(epic)
      end

      it 'raises not found exception when epic does not belong to group' do
        allow(notes_helper).to receive(:user_group).and_return(other_group)

        expect { notes_helper.find_noteable(noteable_type, epic.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
