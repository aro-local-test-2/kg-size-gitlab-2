# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::DiffShape, feature_category: :duo_code_review do
  using RSpec::Parameterized::TableSyntax

  let(:merge_request) { build(:merge_request) }
  let(:stats) { [] }

  # DiffStatsCollection just wraps an enumerable of objects responding to
  # path/additions/deletions, so the real collection can be used here.
  let(:diff_stats) { Gitlab::Git::DiffStatsCollection.new(stats) }

  subject(:signal) { described_class.new(merge_request) }

  before do
    allow(merge_request).to receive(:diff_stats).and_return(diff_stats)
  end

  def stat(path, additions: 1, deletions: 0)
    Struct.new(:path, :additions, :deletions).new(path, additions, deletions)
  end

  it_behaves_like 'a signal with dimensions', 'Change shape', {
    churn: 'Size of change',
    breadth: 'Number of files changed',
    dispersion: 'Spread across subsystems',
    entropy: 'Concentration of the change across files',
    net_growth: 'Proportion of added to removed lines'
  }

  describe '#available?' do
    context 'when there are diff stats' do
      let(:stats) { [stat('a.rb')] }

      it { is_expected.to be_available }
    end

    context 'when diff stats cannot be produced' do
      before do
        allow(merge_request).to receive(:diff_stats).and_return(nil)
      end

      it { is_expected.not_to be_available }
    end
  end

  describe '#extract' do
    describe 'churn' do
      where(:additions, :deletions, :expected) do
        [
          [0,    0,    0.0],
          [50,   50,   0.2],
          [250,  250,  1.0],
          [5000, 5000, 1.0]
        ]
      end

      with_them do
        let(:stats) { [stat('a.rb', additions: additions, deletions: deletions)] }

        it 'ramps with lines changed and saturates' do
          expect(signal.extract[:churn]).to eq(expected)
        end
      end
    end

    describe 'breadth' do
      context 'with a single file' do
        let(:stats) { [stat('a.rb')] }

        it 'is near zero' do
          expect(signal.extract[:breadth]).to be < 0.1
        end
      end

      context 'with more files than the saturation point' do
        let(:stats) { Array.new(described_class::FILES_SATURATE_AT + 5) { |i| stat("dir/file_#{i}.rb") } }

        it 'saturates' do
          expect(signal.extract[:breadth]).to eq(1.0)
        end
      end
    end

    describe 'dispersion' do
      context 'when the change sits in one top level directory' do
        let(:stats) { [stat('app/models/a.rb'), stat('app/models/b.rb'), stat('app/services/c.rb')] }

        it 'reports no dispersion, however many files are touched' do
          expect(signal.extract[:dispersion]).to eq(0.0)
        end
      end

      context 'with two top level directories' do
        let(:stats) { [stat('app/a.rb'), stat('ee/b.rb')] }

        it 'reports partial dispersion' do
          expect(signal.extract[:dispersion]).to eq(0.2)
        end
      end

      context 'when the change is scattered across unrelated subsystems' do
        let(:stats) do
          %w[app/a.rb ee/b.rb lib/c.rb config/d.yml db/e.rb doc/f.md].map { |path| stat(path) }
        end

        it 'saturates' do
          expect(signal.extract[:dispersion]).to eq(1.0)
        end
      end
    end

    context 'with an extreme change' do
      let(:stats) do
        Array.new(200) { |i| stat("dir_#{i}/file.rb", additions: 500, deletions: 500) }
      end

      it 'keeps every value normalized' do
        expect(signal.extract.values).to all(be_between(0.0, 1.0))
      end
    end

    describe 'entropy' do
      context 'with a single file' do
        let(:stats) { [stat('a.rb', additions: 100)] }

        it 'reports no scatter' do
          expect(signal.extract[:entropy]).to eq(0.0)
        end
      end

      context 'when the lines are concentrated in one of many files' do
        let(:stats) { [stat('a.rb', additions: 997), stat('b.rb'), stat('c.rb'), stat('d.rb')] }

        it 'stays low even though several files are touched' do
          expect(signal.extract[:entropy]).to be < 0.1
        end
      end

      context 'when the lines are spread evenly' do
        let(:stats) { Array.new(4) { |i| stat("file_#{i}.rb", additions: 100) } }

        it 'saturates' do
          expect(signal.extract[:entropy]).to eq(1.0)
        end
      end
    end

    describe 'net_growth' do
      where(:additions, :deletions, :expected) do
        [
          [0,   100, 0.0],
          [50,  50,  0.5],
          [100, 0,   1.0],
          [0,   0,   0.0]
        ]
      end

      with_them do
        let(:stats) { [stat('a.rb', additions: additions, deletions: deletions)] }

        it 'reports the share of changed lines that are additions' do
          expect(signal.extract[:net_growth]).to eq(expected)
        end
      end
    end

    describe 'generated files' do
      let(:stats) do
        [
          stat('app/models/a.rb', additions: 10),
          stat('Gemfile.lock', additions: 5000),
          stat('db/structure.sql', additions: 5000),
          stat('node_modules/x/index.js', additions: 5000)
        ]
      end

      it 'excludes them from every dimension' do
        expect(signal.extract).to include(
          churn: 0.02,
          breadth: 0.0333,
          dispersion: 0.0,
          entropy: 0.0
        )
      end

      context 'when every changed file is generated' do
        let(:stats) { [stat('yarn.lock', additions: 5000)] }

        it 'reports no shape rather than reporting unavailable' do
          expect(signal.extract.values).to all(eq(0.0))
        end
      end
    end

    it 'reports exactly the shape dimensions' do
      expect(signal.extract.keys).to contain_exactly(:churn, :breadth, :dispersion, :entropy, :net_growth)
    end
  end
end
