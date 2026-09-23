# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::TestCoverage, feature_category: :duo_code_review do
  let(:merge_request) { build(:merge_request) }
  let(:modified_paths) { ['app/a.rb'] }
  let(:artifact) { nil }
  let(:pipeline) { instance_double(Ci::Pipeline) }

  subject(:signal) { described_class.new(merge_request) }

  before do
    allow(merge_request).to receive_messages(modified_paths: modified_paths, diff_head_pipeline: pipeline)

    if pipeline
      pipeline_artifacts = double('pipeline_artifacts') # rubocop:disable RSpec/VerifiedDoubles -- association proxy, not a fixed class
      allow(pipeline).to receive(:pipeline_artifacts).and_return(pipeline_artifacts)
      allow(pipeline_artifacts).to receive(:find_by_file_type).with(:code_coverage).and_return(artifact)
    end
  end

  def stub_coverage(files)
    presenter = instance_double(Ci::PipelineArtifacts::CodeCoveragePresenter)
    allow(presenter).to receive(:for_files).with(modified_paths).and_return({ files: files })

    instance_double(Ci::PipelineArtifact, present: presenter)
  end

  it_behaves_like 'a signal with dimensions', 'Test coverage', {
    uncovered_lines: 'Uncovered changed lines'
  }

  describe '#available?' do
    context 'when there is no coverage artifact' do
      it { is_expected.not_to be_available }
    end

    context 'when there is no head pipeline' do
      let(:pipeline) { nil }

      it { is_expected.not_to be_available }
    end

    context 'when the report covers none of the changed paths' do
      let(:artifact) { stub_coverage({}) }

      it 'is unavailable, because coverage is unknown rather than absent' do
        is_expected.not_to be_available
      end
    end

    context 'when the report covers a changed path' do
      let(:artifact) { stub_coverage({ 'app/a.rb' => { '1' => 1 } }) }

      it { is_expected.to be_available }
    end
  end

  describe '#extract' do
    context 'when every changed line is covered' do
      let(:artifact) { stub_coverage({ 'app/a.rb' => { '1' => 3, '2' => 1 } }) }

      it 'reports nothing uncovered' do
        expect(signal.extract).to eq({ uncovered_lines: 0.0 })
      end
    end

    context 'when no changed line is covered' do
      let(:artifact) { stub_coverage({ 'app/a.rb' => { '1' => 0, '2' => 0 } }) }

      it 'reports fully uncovered' do
        expect(signal.extract).to eq({ uncovered_lines: 1.0 })
      end
    end

    context 'when coverage is partial' do
      let(:artifact) { stub_coverage({ 'app/a.rb' => { '1' => 1, '2' => 0, '3' => 0, '4' => 5 } }) }

      it 'reports the uncovered proportion' do
        expect(signal.extract).to eq({ uncovered_lines: 0.5 })
      end
    end

    context 'when some lines are not instrumented' do
      let(:artifact) { stub_coverage({ 'app/a.rb' => { '1' => 1, '2' => nil, '3' => 0 } }) }

      it 'ignores nil hit counts rather than counting them as uncovered' do
        expect(signal.extract).to eq({ uncovered_lines: 0.5 })
      end
    end

    context 'with several changed files' do
      let(:modified_paths) { ['app/a.rb', 'app/b.rb'] }
      let(:artifact) do
        stub_coverage({ 'app/a.rb' => { '1' => 1 }, 'app/b.rb' => { '1' => 0, '2' => 0, '3' => 0 } })
      end

      it 'pools lines across files' do
        expect(signal.extract).to eq({ uncovered_lines: 0.75 })
      end
    end
  end
end
