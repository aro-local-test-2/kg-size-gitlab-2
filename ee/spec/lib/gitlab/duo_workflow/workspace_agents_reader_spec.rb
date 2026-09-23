# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::DuoWorkflow::WorkspaceAgentsReader, feature_category: :duo_agent_platform do
  let_it_be(:project) do
    create(:project, :custom_repo, files: {
      '.agents/agents/reviewer.md' =>
        "---\nname: reviewer\ndescription: Reviews diffs.\ntools: read_file, grep\n---\n\nBe picky about naming.\n",
      '.agents/agents/tester.md' =>
        "---\ndescription: Runs tests.\ntools:\n  - run_command\n  - read_file\n---\nRun the tests.\n",
      '.agents/agents/no-description.md' => "---\nname: nope\n---\nPrompt.\n",
      '.agents/agents/no-prompt.md' => "---\ndescription: Nothing to say.\n---\n",
      '.agents/agents/no-front-matter.md' => "Just a prompt.\n",
      '.agents/agents/broken.md' => "---\nname: [unterminated\n---\nPrompt.\n",
      '.agents/agents/aliased.md' => "---\nname: &a aliased\ndescription: *a\n---\nPrompt.\n",
      '.agents/agents/binary.md' => File.binread(Rails.root.join('spec/fixtures/dk.png')),
      '.agents/agents/huge.md' => "---\ndescription: Huge.\n---\n#{'a' * 70_000}",
      '.agents/agents/notes.txt' => "---\ndescription: Not an agent.\n---\nPrompt.\n",
      '.agents/agents/nested/inner.md' => "---\ndescription: Nested.\n---\nPrompt.\n"
    })
  end

  subject(:agents) { described_class.new(project).agents }

  before do
    allow(Gitlab::AppJsonLogger).to receive(:warn)
  end

  describe '#agents' do
    it 'returns one agent per valid Markdown file directly in the directory, in path order' do
      expect(agents.map { |agent| agent['name'] }).to eq(%w[reviewer tester])
    end

    it 'builds an agent from the front matter and the prompt body' do
      expect(agents.first).to eq(
        'name' => 'reviewer',
        'description' => 'Reviews diffs.',
        'toolset' => %w[read_file grep],
        'prompt' => 'Be picky about naming.'
      )
    end

    it 'defaults the name to the file name and accepts tools as a list' do
      expect(agents.last).to eq(
        'name' => 'tester',
        'description' => 'Runs tests.',
        'toolset' => %w[run_command read_file],
        'prompt' => 'Run the tests.'
      )
    end

    it 'logs each skipped file with its reason', :aggregate_failures do
      agents

      {
        '.agents/agents/no-description.md' => 'is missing a description or a prompt',
        '.agents/agents/no-prompt.md' => 'is missing a description or a prompt',
        '.agents/agents/no-front-matter.md' => 'has no YAML front matter',
        '.agents/agents/broken.md' => 'has invalid YAML front matter',
        '.agents/agents/aliased.md' => 'has invalid YAML front matter',
        '.agents/agents/binary.md' => 'is not a UTF-8 text file',
        '.agents/agents/huge.md' => "is larger than #{described_class::MAX_FILE_SIZE} bytes"
      }.each do |path, reason|
        expect(Gitlab::AppJsonLogger).to have_received(:warn).with(
          hash_including('message' => 'Skipping workspace agent file', 'gl_project_id' => project.id, 'path' => path,
            'additional_details' => reason)
        )
      end
    end

    context 'when more files exist than the limit allows' do
      before do
        stub_const("#{described_class}::MAX_AGENTS", 8)
      end

      it 'reads only the first files in path order and logs the rest', :aggregate_failures do
        expect(project.repository).to receive(:blobs_at)
          .with(an_object_having_attributes(size: 8), blob_size_limit: described_class::MAX_FILE_SIZE)
          .and_call_original

        expect(agents.map { |agent| agent['name'] }).to eq(%w[reviewer])

        expect(Gitlab::AppJsonLogger).to have_received(:warn).with(
          hash_including('message' => 'Ignoring workspace agent files over the limit', 'gl_project_id' => project.id,
            'limit' => 8, 'paths' => %w[.agents/agents/tester.md])
        )
      end
    end

    context 'when the repository read fails' do
      before do
        allow(project.repository).to receive(:tree).and_raise(Gitlab::Git::CommandError, 'Gitaly unavailable')
      end

      it 'tracks the error and returns no agents' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(Gitlab::Git::CommandError), project_id: project.id)

        expect(agents).to eq([])
      end
    end

    context 'when the repository has no default branch' do
      let_it_be(:project) { create(:project) }

      it 'returns no agents' do
        expect(agents).to eq([])
      end
    end

    context 'when the directory is absent' do
      let_it_be(:project) { create(:project, :custom_repo, files: { 'README.md' => '' }) }

      it 'returns no agents' do
        expect(agents).to eq([])
      end
    end
  end
end
