# frozen_string_literal: true

require 'spec_helper'

# Parity spec: `Note.without_hidden` drops banned authors' notes on the Postgres
# path, and `NotePolicy` has no banned-author rule to backstop the ES path.
RSpec.describe 'Notes search excludes banned authors', :elastic_delete_by_query, :sidekiq_inline,
  feature_category: :global_search do
  let_it_be(:project) { create(:project, :public) }
  let_it_be(:issue) { create(:issue, project: project) }
  let_it_be(:searching_user) { create(:user) }

  # Banned on build: `let_it_be` deep-freezes its records, so an in-example
  # `ban!` raises FrozenError.
  let_it_be(:banned_author) { create(:user, :banned) }
  let_it_be(:regular_note) { create(:note_on_issue, project: project, noteable: issue, note: 'findmeterm ok') }
  let_it_be(:banned_note) do
    create(:note_on_issue, project: project, noteable: issue, note: 'findmeterm banned', author: banned_author)
  end

  let(:es_options) do
    { current_user: searching_user, project_ids: [project.id], search_level: :project }
  end

  def es_note_ids(user: searching_user)
    Note.elastic_search('findmeterm', options: es_options.merge(current_user: user)).records.map(&:id)
  end

  def pg_note_ids(user: searching_user)
    NotesFinder.new(user, project: project, search: 'findmeterm',
      organization_id: project.organization_id).execute.map(&:id)
  end

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
  end

  it 'confirms the fixtures model the gap: the author is banned and the note is hidden' do
    expect(banned_author.banned?).to be(true)
    expect(banned_note.hidden?).to be(true)
    expect(regular_note.hidden?).to be(false)
  end

  context 'when the notes hidden backfill has finished' do
    before do
      set_elasticsearch_migration_to(:backfill_hidden_on_notes, including: true)
      Elastic::ProcessBookkeepingService.track!(regular_note, banned_note)
      ensure_elasticsearch_index!
    end

    it 'excludes the banned author note from Elasticsearch results' do
      expect(es_note_ids).to contain_exactly(regular_note.id)
      expect(es_note_ids).not_to include(banned_note.id)
    end

    it 'matches the Postgres path exactly' do
      expect(es_note_ids).to match_array(pg_note_ids)
    end

    it 'still returns the note to a user who can admin all resources', :enable_admin_mode do
      admin = create(:admin)

      expect(es_note_ids(user: admin)).to include(banned_note.id)
      expect(pg_note_ids(user: admin)).to include(banned_note.id)
    end

    it 'applies the not_hidden named query' do
      es_note_ids

      assert_named_queries('filters:not_hidden')
    end
  end

  context 'when the notes hidden backfill has not finished' do
    before do
      set_elasticsearch_migration_to(:backfill_hidden_on_notes, including: false)
      Elastic::ProcessBookkeepingService.track!(regular_note, banned_note)
      ensure_elasticsearch_index!
    end

    # Filtering here would drop every un-backfilled note, since a `term` filter
    # does not match a document missing the field.
    it 'does not filter, and does not drop unbackfilled notes either' do
      expect(es_note_ids).to contain_exactly(regular_note.id, banned_note.id)

      assert_named_queries('note:multi_match:and:search_terms', without: ['filters:not_hidden'])
    end
  end
end
