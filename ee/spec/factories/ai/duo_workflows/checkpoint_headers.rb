# frozen_string_literal: true

FactoryBot.define do
  factory :duo_workflows_checkpoint_header, class: 'Ai::DuoWorkflows::CheckpointHeader' do
    workflow { association(:duo_workflows_workflow) }
    thread_ts { Gitlab::Utils.uuid_v7 }
    parent_ts { Gitlab::Utils.uuid_v7 }
    current_thread { 0 }
    checkpoint { { 'v' => 1, 'channel_versions' => {}, 'versions_seen' => {} } }
    metadata { { 'source' => 'loop' } }
    # The default checkpoint carries no channel_values, so this derives []: a header
    # that declares no live channels, and folds that reconstruct from it return {}.
    # Pass the live channels explicitly, or nil for a header written before the column.
    channel_keys { (checkpoint.with_indifferent_access[:channel_values] || {}).keys }
    project { workflow.project }
    # Mirror the write path: the partition key is the workflow's created_at.
    # Fallback for the build strategy, where the workflow is not persisted and
    # created_at is nil (the column is NOT NULL).
    workflow_created_at { workflow.created_at || Time.current }
  end
end
