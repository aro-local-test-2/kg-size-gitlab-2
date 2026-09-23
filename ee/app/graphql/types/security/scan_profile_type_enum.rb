# frozen_string_literal: true

module Types
  module Security
    class ScanProfileTypeEnum < BaseEnum
      graphql_name 'SecurityScanProfileType'
      description 'Scan profile type'

      Enums::Security.scan_profile_types.each_key do |name|
        value(
          name.to_s.upcase,
          value: name.to_s,
          description: name.to_s.humanize
        )
      end

      Enums::Security.remediation_scan_profile_types.except(:triage_and_remediation).each_key do |name|
        value(
          name.to_s.upcase,
          value: name.to_s,
          description: "#{name.to_s.humanize}.",
          experiment: { milestone: '19.2' }
        )
      end

      value 'TRIAGE_AND_REMEDIATION',
        value: 'triage_and_remediation',
        description: 'Triage and remediation.',
        experiment: { milestone: '19.4' }
    end
  end
end
