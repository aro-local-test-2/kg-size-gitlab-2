# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::ScanProfiles::SastConfigurationType, feature_category: :security_testing_configuration do
  it { expect(described_class.graphql_name).to eq('SastConfiguration') }

  it 'exposes the expected fields' do
    expect(described_class).to have_graphql_fields(
      :secure_analyzers_prefix,
      :image_suffix,
      :analyzer_image_tag,
      :excluded_analyzers,
      :excluded_paths,
      :advanced_sast_partial_scan,
      :gitlab_adv_sast_incr_scan
    )
  end
end
