# frozen_string_literal: true

RSpec.shared_examples 'a surface gated on a configured Artifact Registry base URL' do |hidden_example|
  context 'when the instance configures no Artifact Registry' do
    before do
      stub_config(artifact_registry: {})
    end

    it_behaves_like hidden_example
  end

  context 'when the configured base URL names no usable origin' do
    before do
      stub_config(artifact_registry: { api_url: 'ftp://artifact-registry.example.com' })
    end

    it_behaves_like hidden_example
  end
end
