# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::DependencyManifest, feature_category: :duo_code_review do
  using RSpec::Parameterized::TableSyntax

  let(:merge_request) { build(:merge_request) }
  let(:stats) { [] }

  let(:diff_stats) { Gitlab::Git::DiffStatsCollection.new(stats) }

  subject(:signal) { described_class.new(merge_request) }

  before do
    allow(merge_request).to receive(:diff_stats).and_return(diff_stats)
  end

  def stat(path)
    Struct.new(:path, :additions, :deletions).new(path, 1, 0)
  end

  it_behaves_like 'a signal with dimensions', 'Dependency changes', {
    touched: 'Dependency files changed',
    direct_change: 'Manifest file changed directly',
    ecosystems: 'Number of dependency ecosystems touched'
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
    context 'when no dependency file is touched' do
      let(:stats) { [stat('app/models/a.rb'), stat('README.md')] }

      it 'reports no risk' do
        expect(signal.extract[:touched]).to eq(0.0)
      end
    end

    where(:path) do
      [
        ['Gemfile'],
        ['Gemfile.lock'],
        ['package.json'],
        ['package-lock.json'],
        ['yarn.lock'],
        ['pnpm-lock.yaml'],
        ['go.mod'],
        ['go.sum'],
        ['Cargo.toml'],
        ['Cargo.lock'],
        ['composer.json'],
        ['composer.lock'],
        ['Pipfile'],
        ['Pipfile.lock'],
        ['requirements.txt'],
        ['ee/Gemfile.lock'],
        ['app/assets/package.json']
      ]
    end

    with_them do
      let(:stats) { [stat(path)] }

      it 'reports maximum risk regardless of directory' do
        expect(signal.extract[:touched]).to eq(1.0)
      end
    end

    describe 'direct_change' do
      context 'when only a lockfile moves' do
        let(:stats) { [stat('Gemfile.lock')] }

        it 'reports a transitive refresh rather than a deliberate change' do
          expect(signal.extract[:direct_change]).to eq(0.0)
        end
      end

      context 'when a manifest moves' do
        let(:stats) { [stat('Gemfile'), stat('Gemfile.lock')] }

        it 'reports a deliberate change' do
          expect(signal.extract[:direct_change]).to eq(1.0)
        end
      end
    end

    describe 'ecosystems' do
      context 'when a manifest and its lockfile move together' do
        let(:stats) { [stat('Gemfile'), stat('Gemfile.lock')] }

        it 'counts one ecosystem, not two files' do
          expect(signal.extract[:ecosystems]).to eq(0.0)
        end
      end

      context 'with two ecosystems' do
        let(:stats) { [stat('Gemfile.lock'), stat('package-lock.json')] }

        it 'reports partial spread' do
          expect(signal.extract[:ecosystems]).to eq(0.5)
        end
      end

      context 'with more ecosystems than the saturation point' do
        let(:stats) { [stat('Gemfile'), stat('package.json'), stat('go.mod'), stat('Cargo.toml')] }

        it 'saturates' do
          expect(signal.extract[:ecosystems]).to eq(1.0)
        end
      end
    end

    it 'reports exactly the dependency dimensions' do
      expect(signal.extract.keys).to contain_exactly(:touched, :direct_change, :ecosystems)
    end
  end
end
