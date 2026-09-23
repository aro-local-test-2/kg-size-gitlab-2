# frozen_string_literal: true

require "spec_helper"

RSpec.describe PackageMetadata::License, feature_category: :software_composition_analysis do
  describe "validations" do
    it { is_expected.to validate_length_of(:spdx_identifier).is_at_most(50).allow_nil }
    it { is_expected.to validate_length_of(:spdx_expression).is_at_most(1024).allow_nil }

    it "is invalid when both spdx_identifier and spdx_expression are nil" do
      expect(build(:pm_license, spdx_identifier: nil, spdx_expression: nil)).not_to be_valid
    end

    it "is valid when only spdx_identifier is present" do
      expect(build(:pm_license, spdx_identifier: "MIT", spdx_expression: nil)).to be_valid
    end

    it "is valid when only spdx_expression is present" do
      expect(build(:pm_license, spdx_identifier: nil, spdx_expression: "MIT OR Apache-2.0")).to be_valid
    end

    it "is invalid when both spdx_identifier and spdx_expression are present" do
      license = described_class.new(spdx_identifier: "MIT", spdx_expression: "MIT OR Apache-2.0")
      expect(license).not_to be_valid
    end
  end

  describe ".with_spdx_identifiers" do
    let_it_be(:identifier_license) { create(:pm_license, spdx_identifier: "MIT", spdx_expression: nil) }
    let_it_be(:expression_license) { create(:pm_license, spdx_identifier: nil, spdx_expression: "MIT OR Apache-2.0") }

    it "returns licenses matching the given identifiers" do
      expect(described_class.with_spdx_identifiers(["MIT"])).to contain_exactly(identifier_license)
    end

    it "does not return expression-only rows" do
      expect(described_class.with_spdx_identifiers(["MIT OR Apache-2.0"])).to be_empty
    end
  end

  describe ".with_spdx_expressions" do
    let_it_be(:identifier_license) { create(:pm_license, spdx_identifier: "MIT2", spdx_expression: nil) }
    let_it_be(:expression_license) do
      create(:pm_license, spdx_identifier: nil, spdx_expression: "GPL-2.0-or-later OR MIT")
    end

    it "returns licenses matching the given expressions" do
      expect(described_class.with_spdx_expressions(["GPL-2.0-or-later OR MIT"])).to contain_exactly(expression_license)
    end

    it "does not return identifier-only rows" do
      expect(described_class.with_spdx_expressions(["MIT2"])).to be_empty
    end
  end
end
