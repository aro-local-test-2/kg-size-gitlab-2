# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../elastic/migrate/20260515123343_reindex_user_to_fix_username_and_name_analyzers'

RSpec.describe ReindexUserToFixUsernameAndNameAnalyzers, feature_category: :global_search do
  it_behaves_like 'a deprecated Advanced Search migration', 20260515123343
end
