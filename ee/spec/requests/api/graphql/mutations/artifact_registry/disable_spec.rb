# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Disabling an Artifact Registry', :use_clean_rails_memory_store_caching,
  feature_category: :artifact_registry do
  it_behaves_like 'an Artifact Registry condition mutation' do
    let(:mutation_name) { :artifact_registry_disable }
    let(:endpoint) { :disable_namespace }
    let(:target_status) { 'disabled' }
  end
end
