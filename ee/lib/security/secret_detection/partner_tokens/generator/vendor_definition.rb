# frozen_string_literal: true

require 'rack/utils'

module Security
  module SecretDetection
    module PartnerTokens
      module Generator
        # A structured, validated description of how to verify one vendor's
        # token. This is the hand-off contract from the AI-assisted rule
        # development process: an LLM reads the vendor's API docs and emits one
        # of these (as YAML), a human reviews it, and the generator turns
        # it into a verifier class + spec that conform to ADR 006.
        #
        # Keeping the AI output as *data* (not code) is what makes scaling to
        # 60+ vendors safe: the generated code is deterministic and reviewable,
        # and every spec is exercised by the same guardrail suite
        # (unknown-never-inactive, ...).
        class VendorDefinition
          Error = Class.new(StandardError)
          InvalidDefinitionError = Class.new(Error)

          # NOTE: 'query' (token in URL) is intentionally not supported yet: the
          # generator would emit an unauthenticated request, which the vendor
          # rejects with 401 and we'd misreport a live token as inactive. Add it
          # only once the generator wires the token into the URL.
          AUTH_STYLES = %w[bearer header basic_username].freeze
          HTTP_METHODS = %w[get post].freeze
          STATUSES = %w[active inactive unknown].freeze
          # Outcomes the generated client raises for instead of returning a status.
          ERROR_OUTCOMES = %w[rate_limit network_error].freeze

          # The generated client class, e.g. AcmeClient; its file name derives
          # from this via #underscore (AcmeClient -> acme_client.rb).
          CLASS_NAME_PATTERN = /\A[A-Z][A-Za-z0-9]*Client\z/
          # Rule ids may carry spaces, dots, dashes and parens, e.g. 'Google (GCP) Service-account'.
          TOKEN_TYPE_PATTERN = /\A[A-Za-z0-9 _.\-()]+\z/
          # Must read as a Ruby symbol, e.g. partner_acme_api.
          RATE_LIMIT_KEY_PATTERN = /\A[a-z][a-z0-9_]*\z/
          # Metrics label, e.g. 'acme'.
          PARTNER_NAME_PATTERN = /\A[A-Za-z0-9 _.-]+\z/
          # An HTTP header name, e.g. DD-API-KEY.
          AUTH_PARAM_PATTERN = /\A[A-Za-z0-9-]+\z/

          attr_reader :token_type, :class_name, :endpoint, :http_method,
            :auth_style, :auth_param, :token_pattern, :status_map,
            :rate_limit_key, :doc_url, :partner_name

          class << self
            # A vendor with several token types gets one definition (and one client)
            # per type. Building them as a set rejects class-name collisions,
            # which would otherwise regenerate the accept-but-cannot-verify
            # mismatch of https://gitlab.com/gitlab-org/gitlab/-/work_items/588454.
            def build_all(attrs_list)
              definitions = attrs_list.map { |attrs| new(attrs) }

              reject_duplicates!('token_type', definitions.map(&:token_type))
              reject_duplicates!('class_name', definitions.map(&:class_name))

              definitions
            end

            private

            def reject_duplicates!(field, values)
              duplicates = values.tally.select { |_value, count| count > 1 }.keys
              return if duplicates.empty?

              raise InvalidDefinitionError, "duplicate #{field}: #{duplicates.join(', ')} -- " \
                'each token type needs its own definition and its own client class'
            end
          end

          # -- straight-line validation of a data definition
          def initialize(attrs)
            attrs = attrs.transform_keys(&:to_s)

            @token_type     = attrs['token_type']
            @class_name     = attrs['class_name']
            @partner_name   = attrs['partner_name'] || derive_partner_name
            @endpoint       = attrs['endpoint']
            @http_method    = (attrs['http_method'] || 'get').to_s.downcase
            @auth_style     = attrs['auth_style'].to_s
            @auth_param     = attrs['auth_param'] # header name / query key
            @token_pattern  = attrs['token_pattern']
            @status_map     = normalize_status_map(attrs['status_map'])
            @rate_limit_key = attrs['rate_limit_key']
            @doc_url        = attrs['doc_url']

            validate!
          end

          # Compiles the declarative status_map into the lookup the generator
          # emits case/when branches and adversarial review read from:
          # HTTP code (Integer) => :active | :inactive | :unknown | :rate_limit | :network_error
          def compiled_status_map
            status_map.each_with_object({}) do |(code, outcome), map|
              # 'default' is documentation-only ('unknown' is the only allowed
              # value); compiling it would produce a bogus 0 => :unknown entry.
              next if code == 'default'

              map[code.to_i] = outcome.to_sym
            end
          end

          def regexp
            Regexp.new(token_pattern)
          end

          private

          # Generated classes always end in Client, so this fits the generator's
          # own output. A vendor with several token types should set partner_name
          # explicitly so all its clients share one metrics label.
          def derive_partner_name
            return unless @class_name

            @class_name.delete_suffix('Client')
          end

          def normalize_status_map(map)
            raise InvalidDefinitionError, 'status_map is required' if map.blank?

            map.transform_keys(&:to_s).transform_values(&:to_s)
          end

          def validate!
            missing = []
            missing << 'token_type' if token_type.blank?
            missing << 'class_name' if class_name.blank?
            missing << 'endpoint' if endpoint.blank?
            missing << 'token_pattern' if token_pattern.blank?
            missing << 'rate_limit_key' if rate_limit_key.blank?
            raise InvalidDefinitionError, "missing required fields: #{missing.join(', ')}" if missing.any?

            if HTTP_METHODS.exclude?(http_method)
              raise InvalidDefinitionError, "http_method must be one of #{HTTP_METHODS.join(', ')}"
            end

            if AUTH_STYLES.exclude?(auth_style)
              raise InvalidDefinitionError, "auth_style must be one of #{AUTH_STYLES.join(', ')}"
            end

            validate_class_name!
            validate_endpoint!
            validate_pattern!
            validate_status_map!
            validate_generated_source_fields!
          end

          def validate_class_name!
            return if class_name.match?(CLASS_NAME_PATTERN)

            raise InvalidDefinitionError, "class_name must be CamelCase ending in 'Client', got #{class_name.inspect}"
          end

          # Every field here is interpolated into generated Ruby source that is
          # written to disk and loaded, so each is constrained to a safe
          # character set: a definition (LLM- or human-authored) must never be
          # able to inject code. The generator also emits via escape-safe
          # forms, but this is the authoritative gate (ADR 006, "data, not code").
          def validate_generated_source_fields!
            unless token_type.match?(TOKEN_TYPE_PATTERN)
              raise InvalidDefinitionError, "token_type has unsafe characters: #{token_type.inspect}"
            end

            unless rate_limit_key.to_s.match?(RATE_LIMIT_KEY_PATTERN)
              raise InvalidDefinitionError,
                "rate_limit_key must be a lowercase symbol name, got #{rate_limit_key.inspect}"
            end

            unless partner_name.to_s.match?(PARTNER_NAME_PATTERN)
              raise InvalidDefinitionError, "partner_name has unsafe characters: #{partner_name.inspect}"
            end

            # Keep the pattern print-safe: it drives sample-token generation and
            # '#' would interpolate (#{}, #@, #$) if it were ever embedded in
            # generated source. No real token format needs it.
            if token_pattern.match?(/#|[^[:print:]]/)
              raise InvalidDefinitionError,
                "token_pattern must not contain '#' or control characters: #{token_pattern.inspect}"
            end

            # doc_url lands in a `#` comment line in generated source; a line
            # break would end the comment and let the rest load as Ruby.
            if doc_url.present? && !doc_url.match?(/\A[[:print:]]*\z/)
              raise InvalidDefinitionError,
                "doc_url must not contain control characters or line breaks: #{doc_url.inspect}"
            end

            if auth_style == 'header' && auth_param.blank?
              raise InvalidDefinitionError, "auth_style 'header' requires auth_param (the header name)"
            end

            return if auth_param.blank? || auth_param.match?(AUTH_PARAM_PATTERN)

            raise InvalidDefinitionError, "auth_param must be a valid HTTP header name, got #{auth_param.inspect}"
          end

          def validate_endpoint!
            uri = URI.parse(endpoint)
            return if uri.is_a?(URI::HTTPS)

            raise InvalidDefinitionError, "endpoint must be an https URL, got #{endpoint.inspect}"
          rescue URI::InvalidURIError => e
            raise InvalidDefinitionError, "endpoint is not a valid URL: #{e.message}"
          end

          def validate_pattern!
            pattern = regexp.source
            # A verifier pattern that isn't anchored will happily match a
            # substring of a longer string and send junk to the vendor. ADR 006
            # requires tight, anchored patterns.
            unless pattern.start_with?('\\A') && pattern.end_with?('\\z')
              raise InvalidDefinitionError, 'token_pattern must be anchored with \\A ... \\z'
            end
          rescue RegexpError => e
            raise InvalidDefinitionError, "token_pattern is not a valid regexp: #{e.message}"
          end

          def validate_status_map!
            # unknown-never-inactive is enforced structurally: the generator
            # hardcodes the fallthrough for unmapped codes to :unknown, so a
            # 'default' entry can only restate that. Anything else -- inactive
            # above all -- would let the definition claim behavior the generated
            # client does not have.
            if status_map.key?('default') && status_map['default'] != 'unknown'
              raise InvalidDefinitionError, "status_map default can only be 'unknown': unmapped codes fall " \
                "through to unknown and must never be inactive, got #{status_map['default'].inspect}"
            end

            allowed = STATUSES + ERROR_OUTCOMES
            status_map.each do |code, outcome|
              unless allowed.include?(outcome)
                raise InvalidDefinitionError,
                  "status_map outcome #{outcome.inspect} must be one of #{allowed.join(', ')}"
              end

              next if code == 'default'

              unless code.match?(/\A\d{3}\z/) && Rack::Utils::HTTP_STATUS_CODES.key?(code.to_i)
                raise InvalidDefinitionError,
                  "status_map key #{code.inspect} must be an HTTP status code"
              end
            end
          end
        end
      end
    end
  end
end
