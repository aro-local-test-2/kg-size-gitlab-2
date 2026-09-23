# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260216152309_add_traversal_ids_to_commits.rb')

RSpec.describe AddTraversalIdsToCommits, feature_category: :global_search do
  it_behaves_like 'a deprecated Advanced Search migration', 20260216152309
end
