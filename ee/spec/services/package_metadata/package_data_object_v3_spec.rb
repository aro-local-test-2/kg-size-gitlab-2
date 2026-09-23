# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::PackageDataObjectV3, feature_category: :software_composition_analysis do
  let(:purl_type) { 'npm' }
  let(:name) { 'cereslib' }
  let(:lowest_version) { '0.2.0' }
  let(:highest_version) { '1.1.9' }
  let(:licenses) { ['MIT'] }
  let(:expressions) { ['Apache-2.0 OR MIT'] }
  let(:default_licenses) { { 'licenses' => licenses, 'expressions' => expressions } }
  let(:other_licenses) do
    [{ 'licenses' => ['GPL-2.0'], 'expressions' => [], 'versions' => ['1.0'] }]
  end

  let(:data) do
    {
      'name' => name,
      'lowest_version' => lowest_version,
      'highest_version' => highest_version,
      'default_licenses' => default_licenses,
      'other_licenses' => other_licenses
    }
  end

  subject(:object) { described_class.create(data, purl_type) }

  describe '.create' do
    context 'with a mixed-case name and an unknown top-level field' do
      let(:name) { 'Django' }
      let(:purl_type) { 'pypi' }
      let(:data) { super().merge('future_field' => 'ignored') }

      it 'normalizes the package name and accepts unknown top-level fields' do
        expect(object.name).to eq('django')
      end
    end

    context 'when default_licenses is absent' do
      let(:data) do
        { 'name' => name, 'lowest_version' => lowest_version, 'highest_version' => highest_version }
      end

      it 'treats absent default_licenses as no licenses' do
        expect(object.spdx_identifiers).to eq([])
        expect(object.spdx_expressions).to eq([])
      end
    end

    context 'when the name key is missing' do
      let(:name) { nil }

      it 'raises ArgumentError' do
        expect { object }.to raise_error(ArgumentError, /name is required/)
      end
    end

    context 'when the optional fields are absent' do
      let(:data) { { 'name' => name, 'default_licenses' => default_licenses } }

      it 'does not raise' do
        expect { object }.not_to raise_error
      end
    end
  end

  describe '#spdx_identifiers' do
    it 'returns identifier strings from default_licenses and other_licenses' do
      expect(object.spdx_identifiers).to match_array(%w[GPL-2.0 MIT])
    end

    context 'when no identifiers are present' do
      let(:licenses) { [] }
      let(:other_licenses) do
        [{ 'expressions' => ['GPL-2.0-or-later OR MIT'], 'versions' => ['1.0'] }]
      end

      it 'returns an empty array' do
        expect(object.spdx_identifiers).to eq([])
      end
    end

    context 'when an identifier appears in both default_licenses and other_licenses' do
      let(:expressions) { [] }
      let(:other_licenses) do
        [{ 'licenses' => ['MIT'], 'versions' => ['1.0'] }]
      end

      it 'deduplicates it' do
        expect(object.spdx_identifiers).to eq(['MIT'])
      end
    end
  end

  describe '#spdx_expressions' do
    context 'with expressions in default_licenses and other_licenses' do
      let(:other_licenses) do
        [{ 'licenses' => [], 'expressions' => ['GPL-2.0-or-later OR MIT'], 'versions' => ['1.0'] }]
      end

      it 'returns the expression strings' do
        expect(object.spdx_expressions).to match_array(['Apache-2.0 OR MIT', 'GPL-2.0-or-later OR MIT'])
      end
    end

    context 'when no expressions are present' do
      let(:expressions) { [] }
      let(:other_licenses) do
        [{ 'licenses' => ['Apache-2.0'], 'versions' => ['1.0'] }]
      end

      it 'returns an empty array' do
        expect(object.spdx_expressions).to eq([])
      end
    end

    context 'when an expression appears in both default_licenses and other_licenses' do
      let(:licenses) { [] }
      let(:expressions) { ['MIT OR Apache-2.0'] }
      let(:other_licenses) do
        [{ 'expressions' => ['MIT OR Apache-2.0'], 'versions' => ['1.0'] }]
      end

      it 'deduplicates it' do
        expect(object.spdx_expressions).to eq(['MIT OR Apache-2.0'])
      end
    end
  end

  describe '#default_identifiers' do
    it 'returns only the identifier strings' do
      expect(object.default_identifiers).to eq(['MIT'])
    end
  end

  describe '#default_expressions' do
    it 'returns only the expression strings' do
      expect(object.default_expressions).to eq(['Apache-2.0 OR MIT'])
    end
  end

  describe '#other_licenses' do
    let(:other_licenses) do
      [{ 'licenses' => ['MIT'], 'expressions' => ['MIT OR Apache-2.0'], 'versions' => ['1.0', '2.0'] }]
    end

    it 'returns entries that keep identifiers and expressions in their own lists' do
      expect(object.other_licenses).to match_array(
        [{ 'licenses' => ['MIT'], 'expressions' => ['MIT OR Apache-2.0'], 'versions' => ['1.0', '2.0'] }]
      )
    end
  end

  describe '#lowest_version' do
    it 'returns the lowest_version from the data' do
      expect(object.lowest_version).to eq(lowest_version)
    end

    context 'when absent' do
      let(:lowest_version) { nil }

      it 'returns nil' do
        expect(object.lowest_version).to be_nil
      end
    end
  end

  describe '#highest_version' do
    it 'returns the highest_version from the data' do
      expect(object.highest_version).to eq(highest_version)
    end

    context 'when absent' do
      let(:highest_version) { nil }

      it 'returns nil' do
        expect(object.highest_version).to be_nil
      end
    end
  end
end
