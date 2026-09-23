# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::TestBalancing::TestSplit, feature_category: :code_testing do
  subject(:test_split) { build(:ci_test_balancing_test_split) }

  it { is_expected.to be_valid }

  describe 'associations' do
    it { is_expected.to belong_to(:project) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:path) }
    it { is_expected.to validate_length_of(:path).is_at_most(1024) }
  end

  it_behaves_like 'cleanup by a loose foreign key' do
    let!(:parent) { create(:project) }
    let!(:model) { create(:ci_test_balancing_test_split, project: parent) }
  end

  describe 'id and path conversion' do
    let_it_be(:project) { create(:project) }
    let_it_be(:test_split_a) { create(:ci_test_balancing_test_split, project: project, path: 'spec/a_spec.rb') }
    let_it_be(:test_split_b) { create(:ci_test_balancing_test_split, project: project, path: 'spec/b_spec.rb') }

    let_it_be(:other_project) { create(:project) }
    let_it_be(:other_split) { create(:ci_test_balancing_test_split, project: other_project, path: 'spec/a_spec.rb') }

    describe '.paths_by_id' do
      it 'returns an id => path map for the given ids' do
        result = described_class.paths_by_id(project.id, [test_split_a.id, test_split_b.id])

        expect(result).to eq(
          test_split_a.id => 'spec/a_spec.rb',
          test_split_b.id => 'spec/b_spec.rb'
        )
      end

      it 'only returns ids that exist' do
        result = described_class.paths_by_id(project.id, [test_split_a.id, non_existing_record_id])

        expect(result).to eq(test_split_a.id => 'spec/a_spec.rb')
      end

      it 'is scoped to the project' do
        result = described_class.paths_by_id(project.id, [test_split_a.id, other_split.id])

        expect(result).to eq(test_split_a.id => 'spec/a_spec.rb')
      end

      it 'returns an empty hash when no ids match' do
        expect(described_class.paths_by_id(project.id, [non_existing_record_id])).to eq({})
      end
    end

    describe '.ids_by_path' do
      it 'returns a path => id map for the given paths' do
        result = described_class.ids_by_path(project.id, ['spec/a_spec.rb', 'spec/b_spec.rb'])

        expect(result).to eq(
          'spec/a_spec.rb' => test_split_a.id,
          'spec/b_spec.rb' => test_split_b.id
        )
      end

      it 'only returns paths that exist' do
        result = described_class.ids_by_path(project.id, ['spec/a_spec.rb', 'spec/missing_spec.rb'])

        expect(result).to eq('spec/a_spec.rb' => test_split_a.id)
      end

      it 'is scoped to the project' do
        create(:ci_test_balancing_test_split, project: other_project, path: 'spec/other_spec.rb')

        result = described_class.ids_by_path(project.id, ['spec/a_spec.rb', 'spec/other_spec.rb'])

        expect(result).to eq('spec/a_spec.rb' => test_split_a.id)
      end

      it 'returns an empty hash when no paths match' do
        expect(described_class.ids_by_path(project.id, ['spec/missing_spec.rb'])).to eq({})
      end
    end
  end

  describe '.fetch_or_create_ids!' do
    let_it_be(:project) { create(:project) }

    subject(:result) { described_class.fetch_or_create_ids!(project.id, paths) }

    context 'when none of the paths exist yet' do
      let(:paths) { ['spec/a_spec.rb', 'spec/b_spec.rb'] }

      it 'inserts them and returns the complete path => id map', :aggregate_failures do
        expect { result }.to change { described_class.count }.by(2)

        expect(result.keys).to match_array(paths)
        expect(result.values).to all(be_a(Integer))
      end
    end

    context 'when all of the paths already exist' do
      let(:paths) { ['spec/a_spec.rb', 'spec/b_spec.rb'] }

      let_it_be(:existing_a, reload: true) do
        create(:ci_test_balancing_test_split, project: project, path: 'spec/a_spec.rb')
      end

      let_it_be(:existing_b, reload: true) do
        create(:ci_test_balancing_test_split, project: project, path: 'spec/b_spec.rb')
      end

      it 'inserts nothing and returns the existing ids', :aggregate_failures do
        expect(described_class).not_to receive(:bulk_insert!)
        expect { result }.not_to change { described_class.count }

        expect(result).to eq(
          'spec/a_spec.rb' => existing_a.id,
          'spec/b_spec.rb' => existing_b.id
        )
      end

      it 'refreshes last_seen_at for stale existing rows' do
        existing_a.update_column(:last_seen_at, (Ci::TestBalancing::LAST_SEEN_THROTTLE_INTERVAL + 1.hour).ago)

        result

        expect(existing_a.reload.last_seen_at).to be_within(1.minute).of(Time.current)
      end

      it 'does not rewrite last_seen_at within the throttle window' do
        existing_a.update_column(:last_seen_at, 1.hour.ago)

        expect { result }.not_to change { existing_a.reload.last_seen_at }
      end
    end

    context 'when only some of the paths exist' do
      let(:paths) { ['spec/existing_spec.rb', 'spec/new_spec.rb'] }

      let_it_be(:existing) { create(:ci_test_balancing_test_split, project: project, path: 'spec/existing_spec.rb') }

      it 'inserts only the missing paths and returns the full map', :aggregate_failures do
        expect { result }.to change { described_class.count }.by(1)

        expect(result.keys).to match_array(paths)
        expect(result['spec/existing_spec.rb']).to eq(existing.id)
        expect(result['spec/new_spec.rb']).to be_a(Integer)
      end
    end

    context 'when a concurrent insert skips some of our rows' do
      let(:paths) { ['spec/new_spec.rb', 'spec/raced_spec.rb'] }

      let!(:raced) { create(:ci_test_balancing_test_split, project: project, path: 'spec/raced_spec.rb') }

      before do
        allow(described_class).to receive(:ids_by_path).and_call_original
        # The initial lookup misses the raced row (as if it did not exist yet), so
        # it is treated as missing and included in the insert. bulk_insert!'s
        # ON CONFLICT DO NOTHING then skips it (it already exists), excluding it
        # from RETURNING, so it must be recovered by the straggler re-fetch.
        allow(described_class).to receive(:ids_by_path)
          .with(project.id, paths).and_return({})
      end

      it 'recovers the skipped row via the straggler re-fetch', :aggregate_failures do
        expect(result.keys).to match_array(paths)
        expect(result['spec/raced_spec.rb']).to eq(raced.id)
        expect(result['spec/new_spec.rb']).to be_a(Integer)
      end
    end

    context 'when the same path is given more than once' do
      let(:paths) { ['spec/dup_spec.rb', 'spec/dup_spec.rb'] }

      it 'creates it once' do
        expect { result }.to change { described_class.count }.by(1)

        expect(result.keys).to contain_exactly('spec/dup_spec.rb')
      end
    end

    context 'when scoped to a project' do
      let(:paths) { ['spec/shared_spec.rb'] }

      let_it_be(:other_project) { create(:project) }
      let_it_be(:other_project_test_split) do
        create(:ci_test_balancing_test_split, project: other_project, path: 'spec/shared_spec.rb')
      end

      it 'does not reuse ids from a different project' do
        expect { result }.to change { described_class.count }.by(1)

        expect(result['spec/shared_spec.rb']).not_to eq(other_project_test_split.id)
      end
    end

    context 'when a path is invalid' do
      let(:paths) { ['a' * 1025] }

      it 'raises a validation error and inserts nothing', :aggregate_failures do
        expect { result }.to raise_error(ActiveRecord::RecordInvalid)
        expect(described_class.count).to eq(0)
      end
    end
  end

  describe '.touch_last_seen' do
    let_it_be(:project) { create(:project) }
    let_it_be(:test_split, reload: true) { create(:ci_test_balancing_test_split, project: project) }

    it 'updates last_seen_at when older than the throttle window' do
      test_split.update_column(:last_seen_at, (Ci::TestBalancing::LAST_SEEN_THROTTLE_INTERVAL + 1.hour).ago)

      described_class.touch_last_seen([test_split.id])

      expect(test_split.reload.last_seen_at).to be_within(1.minute).of(Time.current)
    end

    it 'is a no-op within the throttle window' do
      test_split.update_column(:last_seen_at, 1.hour.ago)

      expect { described_class.touch_last_seen([test_split.id]) }.not_to change { test_split.reload.last_seen_at }
    end

    it 'is a no-op for an empty list' do
      expect { described_class.touch_last_seen([]) }.not_to change { test_split.reload.last_seen_at }
    end
  end
end
