# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Creating a Coverage Fuzzing Corpus', feature_category: :fuzz_testing do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:current_user) { create(:user) }
  let_it_be(:package) { create(:generic_package, :with_zip_file, project: project, status: :hidden) }

  let(:mutation_name) { :corpus_create }

  let(:mutation) do
    graphql_mutation(
      mutation_name,
      full_path: project.full_path,
      package_id: global_id_of(package)
    )
  end

  def mutation_response
    graphql_mutation_response(mutation_name)
  end

  context 'when the user can create a coverage fuzzing corpus' do
    before_all do
      project.add_developer(current_user)
    end

    before do
      stub_licensed_features(coverage_fuzzing: true)
    end

    it 'creates a new corpus' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to change { AppSec::Fuzzing::Coverage::Corpus.count }.by(1)

      expect(mutation_response['errors']).to be_empty
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :create_coverage_fuzzing_corpus do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
