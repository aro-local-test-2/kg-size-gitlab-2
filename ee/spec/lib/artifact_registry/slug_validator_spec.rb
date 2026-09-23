# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::SlugValidator, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject(:validator) { described_class.new(slug) }

  describe '#result' do
    context 'with a slug that satisfies every rule' do
      where(:slug) do
        [
          'abc',              # minimum length
          'a' * 63,           # maximum length
          'valid-slug-1'
        ]
      end

      with_them do
        it 'succeeds' do
          expect(validator.result).to be_success
          expect(validator).to be_valid
        end
      end
    end

    context 'with a slug that breaks exactly one rule' do
      # Each slug fails only the named rule, so each rule has independent coverage.
      where(:rule, :slug) do
        'too short'              | 'ab'
        'too long'               | ('a' * 64)
        'disallowed character'   | 'bad.slug'
        'non-alphanumeric start' | '-slug'
        'non-alphanumeric end'   | 'slug-'
        'consecutive hyphens'    | 'a--b'
      end

      with_them do
        it 'is refused with the invalid_slug reason' do
          expect(validator).not_to be_valid
          expect(validator.result).to be_error
          expect(validator.result.reason).to eq(:invalid_slug)
        end
      end
    end

    context 'when a slug breaks several rules at once' do
      let(:slug) { 'A' } # too short, disallowed char, non-alphanumeric start

      it 'joins every violated rule into one message', :aggregate_failures do
        message = validator.result.message

        expect(message).to include('must be between 3 and 63 characters')
        expect(message).to include('must contain only lowercase ASCII letters, digits, and hyphens')
        expect(message).to include('must start with an alphanumeric character')
        expect(message).to include('; ')
      end
    end
  end
end
