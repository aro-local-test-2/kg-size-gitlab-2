# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::WorkItems::DecisionType, feature_category: :team_planning do
  let(:fields) do
    %i[id title description resolution_rationale resolved_at archived_at state note_url discussion_id source_link
      resolving_note_id author resolved_by options]
  end

  specify { expect(described_class.graphql_name).to eq('WorkItemDecision') }

  specify { expect(described_class).to have_graphql_fields(fields) }
end
