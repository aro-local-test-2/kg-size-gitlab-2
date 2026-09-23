# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Generator::VendorDefinition, feature_category: :secret_detection do
  let(:valid_attrs) do
    {
      token_type: 'Widgets API token',
      class_name: 'WidgetsClient',
      endpoint: 'https://api.widgets.example/v1/me',
      http_method: 'get',
      auth_style: 'bearer',
      token_pattern: '\\Awgt_[a-z0-9]{20}\\z',
      status_map: { '200' => 'active', '401' => 'inactive', '429' => 'rate_limit', '500' => 'network_error' },
      rate_limit_key: 'partner_widgets_api',
      doc_url: 'https://docs.widgets.example'
    }
  end

  describe 'a valid spec' do
    subject(:spec) { described_class.new(valid_attrs) }

    it 'compiles the status map to integer keys and symbol outcomes' do
      expect(spec.compiled_status_map).to eq(
        200 => :active, 401 => :inactive, 429 => :rate_limit, 500 => :network_error
      )
    end

    it 'derives the partner name from the class name' do
      expect(spec.partner_name).to eq('Widgets')
    end

    it 'exposes a usable Regexp' do
      expect(spec.regexp).to be_a(Regexp)
      expect(spec.regexp).to match('wgt_abcdefghij0123456789')
    end
  end

  describe 'validation' do
    it 'rejects a missing required field' do
      expect { described_class.new(valid_attrs.except(:endpoint)) }
        .to raise_error(described_class::InvalidDefinitionError, /endpoint/)
    end

    it 'names every missing required field' do
      expect { described_class.new(status_map: valid_attrs[:status_map]) }
        .to raise_error(described_class::InvalidDefinitionError,
          /token_type, class_name, endpoint, token_pattern, rate_limit_key/)
    end

    it 'rejects an unsupported http_method' do
      expect { described_class.new(valid_attrs.merge(http_method: 'delete')) }
        .to raise_error(described_class::InvalidDefinitionError, /http_method/)
    end

    it 'rejects a non-https endpoint' do
      expect { described_class.new(valid_attrs.merge(endpoint: 'http://api.widgets.example')) }
        .to raise_error(described_class::InvalidDefinitionError, /https/)
    end

    it 'rejects an endpoint that does not parse as a URL' do
      expect { described_class.new(valid_attrs.merge(endpoint: 'https://api.widgets example')) }
        .to raise_error(described_class::InvalidDefinitionError, /not a valid URL/)
    end

    it 'rejects an unanchored token pattern' do
      expect { described_class.new(valid_attrs.merge(token_pattern: 'wgt_[a-z0-9]{20}')) }
        .to raise_error(described_class::InvalidDefinitionError, /anchored/)
    end

    it 'rejects a token_pattern that is not a valid regexp' do
      expect { described_class.new(valid_attrs.merge(token_pattern: '\\Awgt_[\\z')) }
        .to raise_error(described_class::InvalidDefinitionError, /not a valid regexp/)
    end

    # Regression guard: token_pattern lands in generated source as a Regexp
    # literal, where #{...} would interpolate when the generated file loads.
    it 'rejects a token_pattern containing interpolation characters (source-injection guard)' do
      # rubocop:disable Lint/InterpolationCheck -- the literal #{} is the injection payload under test
      expect { described_class.new(valid_attrs.merge(token_pattern: '\\Awgt_#{1}\\z')) }
        .to raise_error(described_class::InvalidDefinitionError, /must not contain '#'/)
      # rubocop:enable Lint/InterpolationCheck
    end

    it 'rejects a class name that is not CamelCase ending in Client' do
      expect { described_class.new(valid_attrs.merge(class_name: 'widgets')) }
        .to raise_error(described_class::InvalidDefinitionError, /class_name/)
    end

    it 'rejects an unsupported auth style' do
      expect { described_class.new(valid_attrs.merge(auth_style: 'magic')) }
        .to raise_error(described_class::InvalidDefinitionError, /auth_style/)
    end

    it "requires auth_param when auth_style is 'header'" do
      expect { described_class.new(valid_attrs.merge(auth_style: 'header')) }
        .to raise_error(described_class::InvalidDefinitionError, /requires auth_param/)
    end

    it 'rejects an auth_param containing a space' do
      expect { described_class.new(valid_attrs.merge(auth_style: 'header', auth_param: 'X-Api Key')) }
        .to raise_error(described_class::InvalidDefinitionError, /HTTP header name/)
    end

    it 'rejects unsafe characters in token_type' do
      expect { described_class.new(valid_attrs.merge(token_type: "Widgets'; end")) }
        .to raise_error(described_class::InvalidDefinitionError, /token_type/)
    end

    it 'rejects a rate_limit_key that is not a lowercase symbol name' do
      expect { described_class.new(valid_attrs.merge(rate_limit_key: 'Partner-Widgets')) }
        .to raise_error(described_class::InvalidDefinitionError, /rate_limit_key/)
    end

    it 'rejects unsafe characters in partner_name' do
      expect { described_class.new(valid_attrs.merge(partner_name: 'Widgets#')) }
        .to raise_error(described_class::InvalidDefinitionError, /partner_name/)
    end

    it 'rejects a default status of inactive (unknown-never-inactive)' do
      map = valid_attrs[:status_map].merge('default' => 'inactive')
      expect { described_class.new(valid_attrs.merge(status_map: map)) }
        .to raise_error(described_class::InvalidDefinitionError, /never be inactive/)
    end

    it "rejects a default status other than 'unknown'" do
      map = valid_attrs[:status_map].merge('default' => 'active')
      expect { described_class.new(valid_attrs.merge(status_map: map)) }
        .to raise_error(described_class::InvalidDefinitionError, /default can only be 'unknown'/)
    end

    it "accepts a default of 'unknown' and keeps it out of the compiled status map" do
      map = valid_attrs[:status_map].merge('default' => 'unknown')
      spec = described_class.new(valid_attrs.merge(status_map: map))

      expect(spec.compiled_status_map.keys).to match_array([200, 401, 429, 500])
    end

    it 'rejects an empty status_map' do
      expect { described_class.new(valid_attrs.merge(status_map: {})) }
        .to raise_error(described_class::InvalidDefinitionError, /status_map is required/)
    end

    it 'rejects an unknown outcome value' do
      expect { described_class.new(valid_attrs.merge(status_map: { '200' => 'alive' })) }
        .to raise_error(described_class::InvalidDefinitionError, /outcome/)
    end

    it 'rejects a status_map key that is not an HTTP status code' do
      expect { described_class.new(valid_attrs.merge(status_map: { '2xx' => 'active' })) }
        .to raise_error(described_class::InvalidDefinitionError, /must be an HTTP status code/)
    end

    it 'rejects a status_map key that is not an assigned HTTP status code' do
      expect { described_class.new(valid_attrs.merge(status_map: { '999' => 'active' })) }
        .to raise_error(described_class::InvalidDefinitionError, /must be an HTTP status code/)
    end

    # Regression guard: doc_url lands verbatim in a `#` comment line in
    # generated source (see ClientGenerator#client_source). A newline there
    # would end the comment early and let whatever follows run as real Ruby
    # in the generated, loaded verifier file.
    it 'rejects a doc_url containing a newline (source-injection guard)' do
      unsafe_doc_url = "https://docs.widgets.example\nEVIL_CONSTANT = 1"

      expect { described_class.new(valid_attrs.merge(doc_url: unsafe_doc_url)) }
        .to raise_error(described_class::InvalidDefinitionError, /doc_url/)
    end

    it 'rejects a doc_url containing other control characters' do
      expect { described_class.new(valid_attrs.merge(doc_url: "https://docs.widgets.example\t")) }
        .to raise_error(described_class::InvalidDefinitionError, /doc_url/)
    end

    it 'accepts a blank doc_url' do
      expect { described_class.new(valid_attrs.merge(doc_url: nil)) }.not_to raise_error
    end
  end

  describe '.build_all' do
    let(:second_type_attrs) do
      valid_attrs.merge(
        token_type: 'Widgets OAuth token',
        class_name: 'WidgetsOauthClient',
        token_pattern: '\\Awgt_oauth_[a-z0-9]{24}\\z'
      )
    end

    it 'builds one spec per token type for a vendor with several token types' do
      specs = described_class.build_all([valid_attrs, second_type_attrs])

      expect(specs.map(&:class_name)).to contain_exactly('WidgetsClient', 'WidgetsOauthClient')
    end

    it 'rejects two token types emitting the same client class' do
      collision = second_type_attrs.merge(class_name: 'WidgetsClient')

      expect { described_class.build_all([valid_attrs, collision]) }
        .to raise_error(described_class::InvalidDefinitionError, /duplicate class_name/)
    end

    it 'rejects duplicate token types' do
      collision = valid_attrs.merge(class_name: 'OtherClient')

      expect { described_class.build_all([valid_attrs, collision]) }
        .to raise_error(described_class::InvalidDefinitionError, /duplicate token_type/)
    end
  end
end
