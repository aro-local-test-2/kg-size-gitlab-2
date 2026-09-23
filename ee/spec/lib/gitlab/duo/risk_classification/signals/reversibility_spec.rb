# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::Reversibility, feature_category: :duo_code_review do
  let(:merge_request) { build(:merge_request) }
  let(:paths) { [] }
  let(:diff_bodies) { {} }
  let(:persisted) { true }

  let(:diff_files) do
    diff_bodies.map do |path, body|
      instance_double(MergeRequestDiffFile, new_path: path, utf8_diff: body)
    end
  end

  let(:diff_file_relation) { class_double(MergeRequestDiffFile, by_paths: diff_files) }
  let(:merge_request_diff) do
    instance_double(MergeRequestDiff, persisted?: persisted, merge_request_diff_files: diff_file_relation)
  end

  subject(:signal) { described_class.new(merge_request) }

  before do
    allow(merge_request).to receive_messages(
      modified_paths: paths,
      merge_request_diff: merge_request_diff
    )
  end

  it_behaves_like 'a signal with dimensions', 'Reversibility', {
    destructive: 'Destructive database migration'
  }

  describe '#available?' do
    context 'when nothing changed' do
      it { is_expected.not_to be_available }
    end

    context 'when no migration is touched' do
      let(:paths) { ['app/models/a.rb'] }

      it 'is available without reading any diff content' do
        expect(signal).to be_available
      end
    end

    context 'when a migration is touched and its diff can be read' do
      let(:paths) { ['db/migrate/20260101000000_add_widgets.rb'] }
      let(:diff_bodies) { { paths.first => "+ add_column :widgets, :name, :text\n" } }

      it { is_expected.to be_available }
    end

    context 'when a migration is touched but the diff is not persisted' do
      let(:paths) { ['db/migrate/20260101000000_add_widgets.rb'] }
      let(:persisted) { false }

      it { is_expected.not_to be_available }
    end
  end

  describe '#extract' do
    context 'when no migration is touched' do
      let(:paths) { ['app/models/a.rb'] }

      it 'reports no destructive change' do
        expect(signal.extract[:destructive]).to eq(0.0)
      end
    end

    context 'with an additive migration' do
      let(:paths) { ['db/migrate/20260101000000_add_widgets.rb'] }
      let(:diff_bodies) do
        { paths.first => "+++ b/db/migrate/x.rb\n+  def up\n+    add_column :widgets, :name, :text\n+  end\n" }
      end

      it 'reports no destructive change' do
        expect(signal.extract[:destructive]).to eq(0.0)
      end
    end

    context 'when a destructive operation is only removed, not added' do
      let(:paths) { ['db/migrate/20260101000000_add_widgets.rb'] }
      let(:diff_bodies) { { paths.first => "-    remove_column :widgets, :name\n+    add_column :widgets, :name\n" } }

      it 'reports no destructive change' do
        expect(signal.extract[:destructive]).to eq(0.0)
      end
    end

    describe 'destructive operations' do
      where(:added_line) do
        [
          ['    remove_column :widgets, :name'],
          ['    remove_columns :widgets, :name, :size'],
          ['    drop_table :widgets'],
          ['    drop_view :widget_summaries'],
          ['    remove_reference :widgets, :project'],
          ['    remove_timestamps :widgets'],
          ['    execute("DROP TABLE widgets")'],
          ["    execute(<<~SQL)\n+      DELETE FROM widgets WHERE id > 0"],
          ['    connection.execute("TRUNCATE widgets")']
        ]
      end

      with_them do
        let(:paths) { ['db/post_migrate/20260101000000_drop_widgets.rb'] }
        let(:diff_bodies) { { paths.first => "+#{added_line}\n" } }

        it 'reports a destructive change' do
          expect(signal.extract[:destructive]).to eq(1.0)
        end
      end
    end

    describe 'migration path recognition' do
      let(:diff_bodies) { { paths.first => "+    drop_table :widgets\n" } }

      where(:path) do
        [
          ['db/migrate/20260101000000_x.rb'],
          ['db/post_migrate/20260101000000_x.rb'],
          ['ee/db/geo/migrate/20260101000000_x.rb'],
          ['ee/db/embedding/migrate/20260101000000_x.rb'],
          ['db/ci/migrate/20260101000000_x.rb']
        ]
      end

      with_them do
        let(:paths) { [path] }

        it 'reads the migration' do
          expect(signal.extract[:destructive]).to eq(1.0)
        end
      end
    end

    context 'when the destructive change is outside a migration' do
      let(:paths) { ['app/models/widget.rb'] }
      let(:diff_bodies) { { paths.first => "+    Widget.delete_all\n" } }

      it 'is not read at all' do
        expect(signal.extract[:destructive]).to eq(0.0)
      end
    end
  end
end
