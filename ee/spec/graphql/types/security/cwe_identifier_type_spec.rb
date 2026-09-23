# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::CweIdentifierType, feature_category: :security_testing_configuration do
  specify { expect(described_class.graphql_name).to eq('CweIdentifier') }

  describe '.coerce_input' do
    it 'accepts a well-formed identifier at both digit boundaries', :aggregate_failures do
      expect(described_class.coerce_input('CWE-8', nil)).to eq('CWE-8')
      expect(described_class.coerce_input('CWE-99999', nil)).to eq('CWE-99999')
    end

    where(:value) { ['cwe-89', 'CWE-', 'CWE-123456', '89', 'CWE-89 ', 89] }

    with_them do
      it 'rejects the value' do
        expect { described_class.coerce_input(value, nil) }
          .to raise_error(GraphQL::CoercionError, /is not a valid CWE identifier/)
      end
    end
  end
end
