# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Elastic::Latest::NoteInstanceProxy, feature_category: :global_search do
  describe '#as_indexed_json', :elastic_helpers do
    subject(:as_indexed_json) { described_class.new(note).as_indexed_json }

    let_it_be(:note) { create(:note_on_merge_request) }
    let(:noteable) { note.noteable }
    let(:hidden_migration_finished) { true }
    let(:common_attributes) do
      noteable = note.noteable
      traversal_ids = if noteable.respond_to?(:namespace)
                        noteable.namespace.elastic_namespace_ancestry
                      else
                        noteable.project.namespace.elastic_namespace_ancestry
                      end

      {
        id: note.id,
        hashed_root_namespace_id: note.project.namespace.hashed_root_namespace_id,
        project_id: note.project_id,
        noteable_id: note.noteable_id,
        noteable_type: note.noteable_type,
        note: note.note,
        type: note.es_type,
        confidential: note.confidential,
        internal: note.internal,
        hidden: note.hidden?,
        archived: note.project.self_or_ancestors_archived?,
        visibility_level: note.project.visibility_level,
        created_at: note.created_at,
        updated_at: note.updated_at,
        traversal_ids: traversal_ids,
        schema_version: Elastic::Latest::NoteInstanceProxy::SCHEMA_VERSION
      }.with_indifferent_access
    end

    before do
      allow(::Elastic::DataMigrationService).to receive(:migration_has_finished?)
        .with(described_class::HIDDEN_FIELD_MIGRATION).and_return(hidden_migration_finished)
    end

    shared_examples 'does not error when note and noteable has no namespace or project' do
      before do
        allow(note).to receive_messages(project: nil, namespace: nil)
        allow(note.noteable).to receive_messages(project_id: nil, namespace_id: nil)
      end

      it 'does not raise an error' do
        expect { as_indexed_json }.not_to raise_error
      end
    end

    context 'when note is on Issue' do
      let_it_be(:note) { create(:note_on_issue) }
      let(:extra_attributes) do
        {
          issues_access_level: note.project.project_feature.access_level(noteable) || ProjectFeature::DISABLED,
          issue: { assignee_id: noteable.assignee_ids, author_id: noteable.author_id,
                   confidential: noteable.confidential }
        }
      end

      it 'serializes the object as a hash with issue properties' do
        expect(as_indexed_json).to match(common_attributes.merge(extra_attributes))
      end

      it_behaves_like 'does not error when note and noteable has no namespace or project'
    end

    context 'when note is on Snippet' do
      let_it_be(:note) { create(:note_on_project_snippet) }
      let(:extra_attributes) do
        {
          traversal_ids: note.noteable.project.namespace.elastic_namespace_ancestry,
          snippets_access_level: note.project.project_feature.access_level(:snippets)
        }
      end

      it 'serializes the object as a hash with snippet properties' do
        expect(as_indexed_json).to match(common_attributes.merge(extra_attributes))
      end

      it_behaves_like 'does not error when note and noteable has no namespace or project'
    end

    context 'when note is on Commit' do
      let_it_be(:note) { create(:note_on_commit) }
      let(:extra_attributes) do
        { repository_access_level: note.project.project_feature.access_level(:repository) }
      end

      it 'serializes the object as a hash with commit properties' do
        expect(as_indexed_json).to match(common_attributes.merge(extra_attributes))
      end
    end

    context 'when note is on MergeRequest' do
      let_it_be(:note) { create(:note_on_merge_request) }
      let(:extra_attributes) do
        { merge_requests_access_level: note.project.project_feature.access_level(noteable) }
      end

      it 'serializes the object as a hash with merge request properties' do
        expect(as_indexed_json).to match(common_attributes.merge(extra_attributes))
      end

      it_behaves_like 'does not error when note and noteable has no namespace or project'
    end

    it 'raises Elastic::Latest::DocumentShouldBeDeletedFromIndexError when noteable is nil' do
      allow(note).to receive(:noteable).and_return(nil)

      expect { as_indexed_json }.to raise_error(::Elastic::Latest::DocumentShouldBeDeletedFromIndexError)
    end

    describe 'hidden field' do
      context 'when the author is banned' do
        let_it_be(:banned_author) { create(:user, :banned) }
        let_it_be(:note) { create(:note_on_merge_request, author: banned_author) }

        it 'indexes hidden as true' do
          expect(as_indexed_json['hidden']).to be(true)
        end
      end

      context 'when the author is not banned' do
        it 'indexes hidden as false' do
          expect(as_indexed_json['hidden']).to be(false)
        end
      end

      context 'when the author has been deleted' do
        before do
          allow(note).to receive(:author).and_return(nil)
        end

        it 'indexes hidden as false' do
          expect(as_indexed_json['hidden']).to be(false)
        end
      end

      context 'when the add_hidden_to_notes migration has not finished' do
        let(:hidden_migration_finished) { false }

        it 'does not index the field, because the notes mapping is dynamic: strict' do
          expect(as_indexed_json).not_to have_key('hidden')
        end

        it 'indexes the previous schema_version, because the document does not carry the new field' do
          expect(as_indexed_json['schema_version']).to eq(described_class::PREVIOUS_SCHEMA_VERSION)
        end
      end

      # `as_indexed_json` consults the gate twice; unmemoized that is two
      # migration-state lookups per indexed document.
      it 'checks the migration state once per document' do
        as_indexed_json

        expect(::Elastic::DataMigrationService).to have_received(:migration_has_finished?)
          .with(described_class::HIDDEN_FIELD_MIGRATION).once
      end
    end

    describe 'feature_access_levels' do
      using RSpec::Parameterized::TableSyntax

      where(:note_type, :project_feature_permission, :access_level) do
        :note_on_issue                      | ProjectFeature::ENABLED   | 'issues_access_level'
        :note_on_project_snippet            | ProjectFeature::DISABLED  | 'snippets_access_level'
        :note_on_personal_snippet           | nil                       | nil
        :note_on_merge_request              | ProjectFeature::PUBLIC    | 'merge_requests_access_level'
        :note_on_commit                     | ProjectFeature::PRIVATE   | 'repository_access_level'
        :diff_note_on_merge_request         | ProjectFeature::PUBLIC    | 'merge_requests_access_level'
        :diff_note_on_commit                | ProjectFeature::PRIVATE   | 'repository_access_level'
        :diff_note_on_design                | ProjectFeature::ENABLED   | nil
        :legacy_diff_note_on_merge_request  | ProjectFeature::PUBLIC    | 'merge_requests_access_level'
        :legacy_diff_note_on_commit         | ProjectFeature::PRIVATE   | 'repository_access_level'
        :note_on_alert                      | ProjectFeature::PRIVATE   | nil
        :note_on_design                     | ProjectFeature::ENABLED   | nil
        :note_on_epic                       | nil                       | nil
        :note_on_vulnerability              | ProjectFeature::PRIVATE   | nil
        :discussion_note_on_vulnerability   | ProjectFeature::PRIVATE   | nil
        :discussion_note_on_merge_request   | ProjectFeature::PUBLIC    | 'merge_requests_access_level'
        :discussion_note_on_issue           | ProjectFeature::ENABLED   | 'issues_access_level'
        :discussion_note_on_project_snippet | ProjectFeature::DISABLED  | 'snippets_access_level'
        :discussion_note_on_personal_snippet | nil                      | nil
        :discussion_note_on_commit          | ProjectFeature::PRIVATE   | 'repository_access_level'
        :track_mr_picking_note              | nil                       | nil
      end

      with_them do
        let!(:note) { create(note_type) } # rubocop:disable Rails/SaveBang -- create is the factory call
        let(:project) { note.project }

        before do
          if access_level.present?
            project.project_feature.update_attribute(access_level.to_sym, project_feature_permission)
          end
        end

        it 'contains the correct permissions', :aggregate_failures do
          if access_level
            expect(as_indexed_json).to have_key(access_level)
            expect(as_indexed_json[access_level]).to eq(project_feature_permission)
          end

          expected_visibility_level = project&.visibility_level || Gitlab::VisibilityLevel::PRIVATE
          expect(as_indexed_json).to have_key('visibility_level')
          expect(as_indexed_json['visibility_level']).to eq(expected_visibility_level)
        end

        context 'when the project does not exist' do
          before do
            allow(note).to receive(:project).and_return(nil)
          end

          it 'has DISABLED access_level' do
            if access_level
              expect(as_indexed_json).to have_key(access_level)
              expect(as_indexed_json[access_level]).to eq(ProjectFeature::DISABLED)
            end
          end
        end
      end
    end
  end
end
