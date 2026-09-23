# frozen_string_literal: true

require 'fast_spec_helper'

require_relative '../../../../lib/security/dependency_firewall/session_id'

RSpec.describe Security::DependencyFirewall::SessionId, feature_category: :dependency_firewall do
  using RSpec::Parameterized::TableSyntax

  describe '.sanitize' do
    it 'returns a conforming identifier unchanged' do
      expect(described_class.sanitize('abc-123_XYZ')).to eq('abc-123_XYZ')
    end

    it 'accepts a value at exactly the bound' do
      value = 'a' * described_class::MAX_LENGTH

      expect(described_class.sanitize(value)).to eq(value)
    end

    it 'returns nil for a value one character over the bound' do
      value = 'a' * (described_class::MAX_LENGTH + 1)

      expect(described_class.sanitize(value)).to be_nil
    end

    it 'returns nil rather than a stripped variant for a disallowed character' do
      expect(described_class.sanitize('abc def')).to be_nil
    end

    it 'returns nil and raises nothing for an invalid UTF-8 byte sequence' do
      value = +"abc\xFF"

      expect { expect(described_class.sanitize(value)).to be_nil }.not_to raise_error
    end

    it 'returns nil and raises nothing for a binary-encoded value, which Rack can supply' do
      value = (+"abc\xFF").force_encoding(Encoding::ASCII_8BIT)

      expect { expect(described_class.sanitize(value)).to be_nil }.not_to raise_error
    end

    it 'returns nil and raises nothing for a non-ASCII-compatible encoding' do
      value = 'abc'.encode(Encoding::UTF_16LE)

      expect { expect(described_class.sanitize(value)).to be_nil }.not_to raise_error
    end

    # These are what make the character set a control rather than a formatting preference: a
    # relaxed pattern would reopen injection into streamed audit records.
    where(:case_name, :value) do
      [
        ['a newline', "abc\ndef"],
        ['a carriage return', "abc\rdef"],
        ['a tab', "abc\tdef"],
        ['a NUL byte', "abc\u0000def"],
        ['an escape byte', "abc\u001bdef"],
        ['a non-ASCII letter', 'abcdéf']
      ]
    end

    with_them do
      it 'returns nil' do
        expect(described_class.sanitize(value)).to be_nil
      end
    end

    it 'returns nil for nil' do
      expect(described_class.sanitize(nil)).to be_nil
    end

    it 'returns nil for an empty string' do
      expect(described_class.sanitize('')).to be_nil
    end

    it 'returns nil for a whitespace-only string' do
      expect(described_class.sanitize('   ')).to be_nil
    end

    it 'returns nil for a comma-folded value, as Rack produces from a duplicated header' do
      expect(described_class.sanitize('abc-123, abc-123')).to be_nil
    end
  end
end
