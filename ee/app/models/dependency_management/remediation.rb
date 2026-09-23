# frozen_string_literal: true

module DependencyManagement
  # Last known auto-remediation state for one dependency in one manifest.
  # Keyed on the dependency's location rather than the vulnerability it fixes:
  # one bump resolves however many vulnerabilities that dependency has.
  class Remediation < ::SecApplicationRecord
    self.table_name = 'dependency_management_remediations'

    STATES = {
      open: 0,
      dismissed: 1,
      merged: 2
    }.freeze

    belongs_to :project, optional: false
    belongs_to :merge_request, optional: true

    enum :purl_type, ::Enums::Sbom.purl_types
    enum :state, STATES

    validates :purl_type, presence: true
    validates :state, presence: true
    # The unique index is the real guard; this only turns a duplicate into a
    # validation error rather than RecordNotUnique for callers that save.
    validates :package_name, presence: true, length: { maximum: 255 },
      uniqueness: { scope: [:project_id, :purl_type, :input_file_path, :current_version] }
    validates :current_version, presence: true, length: { maximum: 255 }
    validates :target_version, presence: true, length: { maximum: 255 }
    # '' is an unreported path. Empty rather than NULL so the unique index
    # keeps deduping, since Postgres treats NULLs as distinct.
    validates :input_file_path, exclusion: { in: [nil] }, length: { maximum: 1024 }

    # No dedicated column: updated_at serves, but only while the row is
    # dismissed, since any later transition moves it.
    def dismissed_at
      updated_at if dismissed?
    end
  end
end
