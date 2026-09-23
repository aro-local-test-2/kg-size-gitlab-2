# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::TimeCoercion, feature_category: :artifact_registry do
  let(:coercing_class) do
    Class.new do
      include ArtifactRegistry::TimeCoercion

      def coerce(value)
        parse_time(value)
      end
    end
  end

  subject(:coercer) { coercing_class.new }

  describe '#parse_time' do
    it 'coerces a valid ISO8601 string to a DateTime' do
      expect(coercer.coerce('2026-07-01T10:00:00Z')).to eq(DateTime.iso8601('2026-07-01T10:00:00Z'))
    end

    it 'returns nil for nil input' do
      expect(coercer.coerce(nil)).to be_nil
    end

    it 'returns nil for an invalid string rather than raising' do
      expect(coercer.coerce('not-a-timestamp')).to be_nil
    end

    it 'returns nil for non-string input rather than raising' do
      expect(coercer.coerce(12345)).to be_nil
    end

    it 'is private on including classes' do
      expect { coercer.parse_time('2026-07-01T10:00:00Z') }.to raise_error(NoMethodError, /private method/)
    end
  end
end
