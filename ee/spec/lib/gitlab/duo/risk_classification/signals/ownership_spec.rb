# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::Ownership, feature_category: :duo_code_review do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:author) { create(:user) }
  let_it_be(:other_owner) { create(:user) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, author: author) }

  let(:licensed) { true }
  let(:empty_code_owners) { false }
  let(:paths) { ['app/models/a.rb'] }
  let(:entries) { [] }

  let(:loader) do
    instance_double(Gitlab::CodeOwners::Loader, empty_code_owners?: empty_code_owners, entries: entries)
  end

  subject(:signal) { described_class.new(merge_request) }

  before do
    stub_licensed_features(code_owners: licensed)

    allow(merge_request).to receive(:modified_paths).and_return(paths)
    allow(Gitlab::CodeOwners::Loader).to receive(:new).and_return(loader)
  end

  def entry_for(*users)
    owner_line = users.map { |user| "@#{user.username}" }.join(' ')

    Gitlab::CodeOwners::Entry.new('*', owner_line).tap do |entry|
      entry.add_matching_users_from(users)
      entry.add_matching_groups_from([])
    end
  end

  it_behaves_like 'a signal with dimensions', 'Code ownership', {
    unowned: 'Changed paths with no declared owner',
    author_not_owner: 'Author does not own the changed code',
    owner_spread: 'Number of distinct owners'
  }

  describe '#available?' do
    it { is_expected.to be_available }

    context 'when the project is not licensed for code owners' do
      let(:licensed) { false }

      it { is_expected.not_to be_available }
    end

    context 'when the project has no CODEOWNERS file' do
      let(:empty_code_owners) { true }

      it { is_expected.not_to be_available }
    end

    context 'when nothing changed' do
      let(:paths) { [] }

      it { is_expected.not_to be_available }
    end
  end

  describe '#extract' do
    context 'when nothing the merge request touches is owned' do
      it 'reports the change as unowned' do
        expect(signal.extract).to eq(unowned: 1.0, author_not_owner: 1.0, owner_spread: 0.0)
      end
    end

    context 'when the author owns the changed code' do
      let(:entries) { [entry_for(author)] }

      it 'reports no ownership risk' do
        expect(signal.extract).to eq(unowned: 0.0, author_not_owner: 0.0, owner_spread: 0.0)
      end
    end

    context 'when someone else owns the changed code' do
      let(:entries) { [entry_for(other_owner)] }

      it 'reports the author as a non-owner' do
        expect(signal.extract).to include(unowned: 0.0, author_not_owner: 1.0)
      end
    end

    context 'when the author is one of several owners on the same line' do
      let(:entries) { [entry_for(author, other_owner)] }

      it 'credits the author' do
        expect(signal.extract[:author_not_owner]).to eq(0.0)
      end
    end

    describe 'owner_spread' do
      context 'with two owning parties' do
        let(:entries) { [entry_for(author), entry_for(other_owner)] }

        it 'reports partial spread' do
          expect(signal.extract[:owner_spread]).to eq(0.25)
        end
      end

      context 'with more owning parties than the saturation point' do
        let(:entries) { Array.new(described_class::OWNERS_SATURATE_AT + 1) { entry_for(create(:user)) } }

        it 'saturates' do
          expect(signal.extract[:owner_spread]).to eq(1.0)
        end
      end

      context 'when the same owner line matches several paths' do
        let(:entries) { [entry_for(other_owner)] }

        it 'counts owning parties, not entries' do
          expect(signal.extract[:owner_spread]).to eq(0.0)
        end
      end
    end
  end
end
