# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe SecretsManagement::ErrorMapping, feature_category: :secrets_management do
  let(:helper_klass) do
    Class.new do
      include SecretsManagement::ErrorMapping
    end
  end

  let(:helper) { helper_klass.new }

  describe '#sanitize_error_message' do
    using RSpec::Parameterized::TableSyntax

    # rubocop:disable Layout/LineLength -- The RSpec table syntax often requires long lines for errors
    where(:input, :expected) do
      'metadata check-and-set parameter does not match the current version' | "This resource was recently modified. Refresh the page and try again to avoid overwriting newer changes."
      'check-and-set parameter did not match'                               | "This resource was recently modified. Refresh the page and try again to avoid overwriting newer changes."
      'path is already in use'                                              | SecretsManagement::ErrorMapping::DEFAULT_ERROR_MESSAGE
    end
    # rubocop:enable Layout/LineLength

    with_them do
      it 'maps to a user-friendly message' do
        expect(helper.sanitize_error_message(input)).to eq(expected)
      end
    end

    it 'returns default for nil' do
      expect(helper.sanitize_error_message(nil))
        .to eq(SecretsManagement::ErrorMapping::DEFAULT_ERROR_MESSAGE)
    end

    it 'returns default for blank string' do
      expect(helper.sanitize_error_message("   "))
        .to eq(SecretsManagement::ErrorMapping::DEFAULT_ERROR_MESSAGE)
    end

    it 'returns default when no pattern matches' do
      expect(helper.sanitize_error_message("some unexpected low-level driver error"))
        .to eq(SecretsManagement::ErrorMapping::DEFAULT_ERROR_MESSAGE)
    end

    it 'does not map permission-like errors in sanitize_error_message' do
      msg = "unauthorized"
      expect(helper.sanitize_error_message(msg))
        .to eq(SecretsManagement::ErrorMapping::DEFAULT_ERROR_MESSAGE)
    end
  end

  describe '#permission_error?' do
    using RSpec::Parameterized::TableSyntax

    where(:input, :expected) do
      # permission-ish errors (should be treated as ResourceNotAvailable)
      'Unauthorized: missing token'                                          | true
      'permission denied'                                                    | true
      'FORBIDDEN: blocked by policy'                                         | true
      'error executing cel program: Cel "all" blocked authorization'         | true
      'error executing cel program: invalid subject for user authentication' | true

      # non-permission errors
      'record does not exist'                                                  | false
      'invalid format supplied'                                                | false
      'network timeout while connecting'                                       | false
      'error validating token: invalid audience (aud) claim: audience'         | false
      nil                                                                      | false
      '   '                                                                    | false
      'error executing cel program: missing audience'                          | false
      'error executing cel program: token project_id does not match role base' | false
    end

    with_them do
      it 'detects whether message should be treated as a permission/availability error' do
        expect(helper.permission_error?(input)).to eq(expected)
      end
    end
  end

  describe '#not_found_error?' do
    using RSpec::Parameterized::TableSyntax

    where(:input, :expected) do
      SecretsManagement::ErrorMapping::NOT_FOUND_ERROR_MESSAGE | true

      # Only the bare message means an absent resource. OpenBao says "not found"
      # in fault messages too, and those must keep reporting.
      'route entry not found'    | false
      'namespace not found'      | false
      'namespace not found here' | false
      'not found in namespace'   | false
      'Not Found'                | false
      'record does not exist'    | false
      nil                        | false
      '   '                      | false
    end

    with_them do
      it 'matches only the exact not-found message' do
        expect(helper.not_found_error?(input)).to eq(expected)
      end
    end
  end

  describe '#redact_paths' do
    using RSpec::Parameterized::TableSyntax

    # rubocop:disable Layout/LineLength -- The RSpec table syntax often requires long lines for errors
    where(:input, :expected) do
      'no handler for route "secrets/kv/data/explicit/MY_DB_PASSWORD". route entry not found.' | 'no handler for route "[REDACTED]". route entry not found.'
      'no handler for route "a" on namespace "b". route entry or namespace is tainted.'        | 'no handler for route "[REDACTED]" on namespace "[REDACTED]". route entry or namespace is tainted.'
      'not found'                                                                              | 'not found'
      'permission denied'                                                                      | 'permission denied'
      nil                                                                                      | ''
    end
    # rubocop:enable Layout/LineLength

    with_them do
      it 'replaces every quoted segment and leaves the rest of the message intact' do
        expect(helper.redact_paths(input)).to eq(expected)
      end
    end
  end

  describe '#redacted_exception' do
    let(:error_class) { Class.new(StandardError) }
    let(:raw_message) { 'no handler for route "secrets/kv/data/explicit/MY_DB_PASSWORD". route entry not found.' }

    subject(:redacted) { helper.redacted_exception(error) }

    context 'when the error has been raised' do
      let(:error) do
        raise error_class, raw_message
      rescue error_class => e
        e
      end

      it 'keeps the class, the backtrace and the diagnostic text', :aggregate_failures do
        expect(redacted).to be_a(error_class)
        expect(redacted.backtrace).to eq(error.backtrace)
        expect(redacted.message).to eq('no handler for route "[REDACTED]". route entry not found.')
        expect(redacted.message).not_to include('MY_DB_PASSWORD')
      end
    end

    context 'when the error has no backtrace' do
      let(:error) { error_class.new(raw_message) }

      it 'still redacts and leaves the backtrace unset', :aggregate_failures do
        expect(redacted.backtrace).to be_nil
        expect(redacted.message).not_to include('MY_DB_PASSWORD')
      end
    end
  end
end
