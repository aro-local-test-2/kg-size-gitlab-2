# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'

module ArtifactRegistry
  class Client
    include Gitlab::Utils::StrongMemoize

    USER_AGENT = "GitLab/#{Gitlab::VERSION}".freeze
    RETRY_EXCEPTIONS = [Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS, Faraday::ConnectionFailed].flatten.freeze
    # methods: never add POST, a retried provisioning call double-applies. DELETE is out too, since a
    # replayed delete 404s on the artifact the first attempt removed, reporting failure for a success.
    # Excluded connection-wide rather than per call, so a DELETE added later opts out by default.
    RETRY_OPTIONS = {
      max: 1,
      interval: 0,
      exceptions: RETRY_EXCEPTIONS,
      methods: (Faraday::Retry::Middleware::IDEMPOTENT_METHODS - [:delete]).freeze
    }.freeze

    API_VERSION = 'api/v1'
    # The service-facing GitLab API surface (ADR-009), a separate path prefix
    # from the user-facing API_VERSION surface.
    GITLAB_API_VERSION = 'api/gitlab/v1'
    # Resolved once at load rather than interpolated per call: every path on
    # this surface is built from it.
    NAMESPACES_PATH = "#{GITLAB_API_VERSION}/namespaces".freeze

    # The verifications endpoint caps a batch at 1000 ids (ADR-004).
    MAX_VERIFICATION_BATCH = 1000

    # Must match the `HeaderName` constant in Artifact Registry's
    # internal/auth/servicetoken package.
    SERVICE_TOKEN_HEADER = 'Gitlab-Artifact-Registry-Token'

    # {header:, prefix:} transport form each entry point binds, so the shared
    # transport composes what it is handed. The service token carries no prefix:
    # it is a bare shared secret, not an RFC 7235 credential.
    BEARER_FORM = { header: 'Authorization', prefix: 'Bearer ' }.freeze
    SERVICE_TOKEN_FORM = { header: SERVICE_TOKEN_HEADER, prefix: '' }.freeze

    PAGINATION_RELS = %i[next prev].freeze

    PACKAGE_FORMATS = %w[maven npm].freeze
    IMAGE_FORMATS = %w[docker oci].freeze
    # The artifact writes address both collections through one route pair, so they guard on the union.
    ARTIFACT_FORMATS = (PACKAGE_FORMATS + IMAGE_FORMATS).freeze

    # Provisioning anchor tuple values. The client owns the wire contract, so
    # callers pass these through rather than defining their own.
    PLATFORM = 'gitlab'
    ENTITY_TYPE_ORGANIZATION = 'organization'
    BILLING_ENTITY_TYPE_GROUP = 'group'

    # entity_id is the organization's UUID (organizations.uuid, a v7). AR types it
    # as a free string and derives nothing, so the caller is the only guarantee it
    # is a UUID; match the canonical form without pinning the version.
    UUID_REGEX = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    # AR types every parents entry as canonical sha256, but the plan's acceptance keeps a
    # non-canonical one reaching the caller instead of dropped. details skips the snippet
    # redaction every other error field passes through, so shape is the bound here.
    DIGEST_SHAPE_REGEX = /\A[a-z0-9]+(?:[+._-][a-z0-9]+)*:\h{32,128}\z/

    # AR's error envelope is exhaustive, so a JSON error body without one came from an intermediary such as an
    # auth proxy. Only conventional human-readable fields are surfaced; anything else may carry its credentials.
    ERROR_SNIPPET_KEYS = %w[detail message title].freeze

    # Separates an omitted field from an explicit nil, which the contract sends as JSON null.
    NOT_PROVIDED = Object.new.freeze

    class Error < StandardError
      attr_reader :status, :request_id

      def initialize(message = nil, status: nil, request_id: nil)
        super(message)
        @status = status
        @request_id = request_id
      end
    end

    AuthorizationError = Class.new(Error)
    UnavailableError = Class.new(Error)

    ConfigurationError = Class.new(Error)

    class ApiError < Error
      attr_reader :code, :details

      def initialize(message = nil, status: nil, code: nil, request_id: nil, details: nil)
        super(message, status: status, request_id: request_id)
        @code = code
        @details = details
      end
    end

    def initialize(current_user: nil, organization: nil, base_url: nil, token_exchange: nil, service_credential: nil)
      base_url = base_url.presence || Configuration.api_url

      raise ConfigurationError, 'base_url is required' if base_url.blank?

      validate_base_url!(base_url)

      @current_user = current_user
      # The organization the request addresses; the per-user token is minted for
      # it. Optional because service-only clients never mint (they have no user).
      @organization = organization
      @base_url = base_url
      @token_exchange = token_exchange || TokenExchange.new
      @service_credential = service_credential || ServiceCredential.new
    end

    def namespace(uuid:)
      guard_segments!(uuid: uuid)

      # The caller looks up a UUID it persisted itself, so a 404 signals drift
      # between Rails and AR: worth logging for operators, but an expected nil
      # outcome for the caller rather than a raised error.
      nil_on_missing(log: true, uuid: uuid) do
        response = service_request(:get, namespace_path(uuid), uuid: uuid)
        attributes = success_body(response, expected: Hash, uuid: uuid)

        # Every reader would return nil, so a body without an id resolves to a
        # namespace that looks present: the opposite of what a drift check needs.
        raise_unexpected_success(response, uuid: uuid) if attributes['id'].blank?

        Namespace.new(attributes)
      end
    end

    def provision_namespace(slug:, platform:, entity_type:, entity_id:, billing_entity_type:, billing_entity_id:)
      guard_present!(slug: slug, platform: platform, entity_type: entity_type, entity_id: entity_id,
        billing_entity_type: billing_entity_type, billing_entity_id: billing_entity_id)
      guard_uuid!(entity_id: entity_id)

      # AR types every anchor field as a JSON string and its strict decoder
      # rejects a number, so billing_entity_id is coerced here: callers hold it
      # as the billing group's integer id.
      body = {
        slug: slug, platform: platform, entity_type: entity_type, entity_id: entity_id,
        billing_entity_type: billing_entity_type, billing_entity_id: billing_entity_id.to_s
      }

      # AR returns 201 on create and 200 on an exact-anchor replay; both carry
      # the namespace. The POST is never retried: a lost response would
      # double-apply provisioning, so recovery belongs to the calling service.
      response = service_request(:post, namespaces_path, body: body)
      attributes = success_body(response, expected: Hash)

      # A hollow namespace would be persisted as a valid mapping by the caller.
      raise_unexpected_success(response) if attributes['id'].blank?

      Namespace.new(attributes)
    end

    def disable_namespace(uuid:)
      namespace_condition(uuid, 'disable')
    end

    def enable_namespace(uuid:)
      namespace_condition(uuid, 'enable')
    end

    def namespace_details(slug:, include_permissions: false)
      guard_segments!(slug: slug)

      # Logged because this route needs no permission and is scoped to the caller's org, so a 404
      # means the slug or org has drifted, not that the caller simply lacks assignments.
      nil_on_missing(log: true, slug: slug) do
        response = user_request(:get, namespace_details_path(slug), slug: slug,
          query: permissions_query(include_permissions))
        attributes = success_body(response, expected: Hash, slug: slug)

        NamespaceDetails.new(attributes,
          verdicts(attributes['permissions'], scope: :namespace, read: :namespace_details, slug: slug,
            requested: include_permissions))
      end
    end

    def repository(slug:, name:, include_permissions: false)
      guard_segments!(slug: slug, name: name)

      nil_on_missing do
        response = user_request(:get, repository_path(slug, name), slug: slug,
          query: permissions_query(include_permissions))
        attributes = success_body(response, expected: Hash, slug: slug)

        repository_with_verdicts(attributes, read: :repository, slug: slug, requested: include_permissions)
      end
    end

    def repositories(
      slug:, format: nil, kind: nil, sort: nil, order: nil, limit: nil, cursor: nil, include_permissions: false)
      guard_segments!(slug: slug)

      query = { format: format, kind: kind, sort: sort, order: order, limit: limit, cursor: cursor }.compact
        .merge(permissions_query(include_permissions))

      # Logged because an unreachable namespace can equally mean the slug this caller holds has
      # drifted from Artifact Registry's.
      nil_on_missing(log: true, slug: slug) do
        response = user_request(:get, repositories_path(slug), slug: slug, query: query)
        attributes_list, permissions = repository_list(response, slug: slug)

        cursors = link_cursors(response, slug: slug)

        Page.new(
          nodes: attributes_list.map do |attributes|
            repository_with_verdicts(attributes, read: :repositories, slug: slug, requested: include_permissions)
          end,
          next_cursor: cursors[:next],
          prev_cursor: cursors[:prev],
          permissions: verdicts(permissions, scope: :namespace, read: :repositories, slug: slug,
            requested: include_permissions)
        )
      end
    end

    def namespace_statistics(slug:)
      guard_segments!(slug: slug)

      path = namespace_statistics_path(slug)

      # path is logged so this read's 404 is distinguishable from the repositories 404 the same
      # drifted slug also triggers; both otherwise log the bare origin alone.
      nil_on_missing(log: true, slug: slug, path: path) do
        response = user_request(:get, path, slug: slug)
        attributes = success_body(response, expected: Hash, slug: slug)

        raise_unexpected_success(response, slug: slug) if missing_expected_keys?(attributes, 'repositories_count',
          'deduplicated_size_bytes')

        NamespaceStatistics.new(attributes)
      end
    end

    def packages(slug:, repository_name:, format:, limit: nil, cursor: nil)
      guard_format!(format, PACKAGE_FORMATS)

      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'packages',
        row_class: package_class(format), limit: limit, cursor: cursor)
    end

    def images(slug:, repository_name:, format:, limit: nil, cursor: nil)
      guard_format!(format, IMAGE_FORMATS)

      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'images',
        row_class: Image, limit: limit, cursor: cursor)
    end

    def upstream_repositories(slug:, repository_name:, format:)
      guard_format!(format, ARTIFACT_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name)

      path = artifacts_path(slug, repository_name, format, 'upstream_repositories')

      nil_on_missing(log: true, slug: slug) do
        response = user_request(:get, path, slug: slug)
        attributes_list = success_body(response, expected: Array, slug: slug)
        raise_unexpected_success(response, slug: slug) unless attributes_list.all?(Hash)

        attributes_list.map { |attributes| UpstreamRepositoryAssociation.new(attributes) }
      end
    end

    def package(slug:, repository_name:, format:, id:)
      guard_format!(format, PACKAGE_FORMATS)

      artifact(slug: slug, repository_name: repository_name, format: format, collection: 'packages',
        id: id, row_class: package_class(format))
    end

    def image(slug:, repository_name:, format:, id:)
      guard_format!(format, IMAGE_FORMATS)

      artifact(slug: slug, repository_name: repository_name, format: format, collection: 'images',
        id: id, row_class: Image)
    end

    def versions(slug:, repository_name:, format:, package_id:, sort: nil, order: nil, limit: nil, cursor: nil)
      guard_format!(format, PACKAGE_FORMATS)

      # package_id is guarded inside artifact_page (guard_segments!(id:) if sub_collection), the
      # single place every sub-collection read passes through.
      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'packages',
        id: package_id, sub_collection: 'versions', row_class: Version,
        extra_query: { sort: sort, order: order }, limit: limit, cursor: cursor,
        log_context: { id: package_id })
    end

    def version(slug:, repository_name:, format:, version_id:)
      guard_format!(format, PACKAGE_FORMATS)

      # A blank or dot-segment version_id resolves nil here (the single-read guard, so a bad deep
      # link exposes no id-syntax oracle), unlike #version_files, whose sub-collection read raises.
      artifact(slug: slug, repository_name: repository_name, format: format, collection: 'versions',
        id: version_id, row_class: Version)
    end

    def version_statistics(slug:, repository_name:, format:, version_id:)
      guard_format!(format, PACKAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, version_id: version_id)

      path = sub_collection_path(slug, repository_name, format, 'versions', version_id, 'statistics')

      # 404 and 501 both mean no count available: the route exists before its handler, so an
      # unimplemented endpoint answers 501 rather than a real outage; both map to nil, not an error.
      # Note: 501 still emits one error-tracking event before the raise is swallowed.
      nil_on_missing do
        response = user_request(:get, path, slug: slug)

        VersionStatistics.new(success_body(response, expected: Hash, slug: slug))
      end
    rescue UnavailableError => e
      raise unless e.status == 501

      nil
    end

    def version_files(slug:, repository_name:, format:, version_id:, limit: nil, cursor: nil)
      guard_format!(format, PACKAGE_FORMATS)

      # version_id is guarded inside artifact_page (guard_segments!(id:) if sub_collection), the
      # single place every sub-collection read passes through. The endpoint sorts by file_name
      # alone, so no sort or order argument is forwarded.
      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'versions',
        id: version_id, sub_collection: 'files', row_class: file_class(format),
        limit: limit, cursor: cursor, log_context: { id: version_id })
    end

    def npm_dist_tags(slug:, repository_name:, package_id:, limit: nil, cursor: nil)
      # Endpoint sorts by name only and its default order suits this read, so we forward no sort/order
      # arg even though it accepts one. Dist-tags are npm-only, so the format segment is hard-coded
      # 'npm' rather than a caller arg, which would expose an invalid surface for maven.
      artifact_page(slug: slug, repository_name: repository_name, format: 'npm', collection: 'packages',
        id: package_id, sub_collection: 'tags', row_class: NpmDistTag,
        limit: limit, cursor: cursor, log_context: { id: package_id })
    end

    # rubocop:disable Metrics/ParameterLists -- each keyword maps to a distinct AR contract argument
    def manifests(
      slug:, repository_name:, format:, image_id:,
      include_referrers: false, sort: nil, order: nil, limit: nil, cursor: nil)
      guard_format!(format, IMAGE_FORMATS)

      # image_id is guarded inside artifact_page (guard_segments!(id:) if sub_collection), the
      # single place every sub-collection read passes through. include_referrers is coerced so a
      # nil renders to false rather than a bare `?include_referrers=` that AR 400s, and a "false"
      # string reads as false rather than flipping referrers on.
      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'images',
        id: image_id, sub_collection: 'manifests', row_class: Manifest,
        extra_query: { sort: sort, order: order,
                       include_referrers: Gitlab::Utils.to_boolean(include_referrers, default: false) },
        limit: limit, cursor: cursor, log_context: { id: image_id })
    end
    # rubocop:enable Metrics/ParameterLists

    def manifest(slug:, repository_name:, format:, image_id:, digest:)
      guard_format!(format, IMAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name)
      return if malformed_deep_link?(image_id, digest)

      path = manifest_path(slug, repository_name, format, image_id, digest)

      # A digest naming no manifest in the image is the ordinary not-found outcome for a
      # user-supplied deep link, so a 404 resolves nil without logging, like the other single reads.
      nil_on_missing do
        response = user_request(:get, path, slug: slug)
        attributes = success_body(response, expected: Hash, slug: slug)

        # A body without an id is a serialization fault, not a present manifest whose readers are nil.
        raise_unexpected_success(response, slug: slug) if attributes['id'].blank?

        ManifestDetail.new(attributes)
      end
    end

    def manifest_referrers(slug:, repository_name:, format:, image_id:, digest:, limit: nil, cursor: nil)
      guard_format!(format, IMAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name)
      return if malformed_deep_link?(image_id, digest)

      # The referrers list hangs off a single manifest, one segment deeper than a manifests list,
      # so it builds on the member path rather than through artifact_page's collection helper.
      # Every row is itself a manifest, so the list element is the same Manifest value object.
      path = "#{manifest_path(slug, repository_name, format, image_id, digest)}/referrers"

      query = { limit: limit, cursor: cursor }.compact

      # Log both the image id and the digest: the route is keyed on the pair, so a 404 is as likely
      # to be the drifted digest as the image id, and a log carrying only one cannot tell them apart.
      nil_on_missing(log: true, slug: slug, id: image_id, digest: digest) do
        response = user_request(:get, path, slug: slug, query: query)
        attributes_list = success_body(response, expected: Array, slug: slug)
        raise_unexpected_success(response, slug: slug) unless attributes_list.all?(Hash)

        cursors = link_cursors(response, slug: slug)

        Page.new(
          nodes: attributes_list.map { |attributes| Manifest.new(attributes) },
          next_cursor: cursors[:next],
          prev_cursor: cursors[:prev]
        )
      end
    end

    def create_repository(slug:, name:, format:, kind: nil, visibility: nil, description: nil, settings: nil)
      guard_segments!(slug: slug, name: name)
      guard_present!(format: format)
      raise ArgumentError, 'settings is only accepted for a remote repository' if settings && kind != 'remote'
      raise ArgumentError, 'settings is required for a remote repository' if kind == 'remote' && settings.nil?

      body = { name: name, format: format, kind: kind, visibility: visibility, description: description,
               settings: settings }.compact
      response = user_request(:post, repositories_path(slug), slug: slug, body: body)

      Repository.new(success_body(response, expected: Hash, slug: slug))
    end

    def update_repository(slug:, name:, visibility: NOT_PROVIDED, description: NOT_PROVIDED, settings: NOT_PROVIDED)
      guard_segments!(slug: slug, name: name)
      raise ArgumentError, 'settings must not be nil' if settings.nil?

      body = provided_fields(visibility: visibility, description: description, settings: settings)
      raise ArgumentError, 'at least one mutable field is required' if body.empty?

      response = user_request(:patch, repository_path(slug, name), slug: slug, body: body)

      Repository.new(success_body(response, expected: Hash, slug: slug))
    end

    def delete_repository(slug:, name:)
      guard_segments!(slug: slug, name: name)

      response = user_request(:delete, repository_path(slug, name), slug: slug, query: { destructive: true })

      raise_unexpected_success(response, slug: slug) unless [202, 204].include?(response.status)

      true
    rescue ApiError => e
      return true if e.status == 404 && e.code == 'not_found'

      log_error(e, method: :delete, code: e.code, slug: slug) if e.status == 400

      raise
    end

    # @return [void]
    def bulk_delete_artifacts(slug:, repository_name:, format:)
      guard_format!(format, ARTIFACT_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name)

      path = bulk_delete_path(slug, repository_name, format, artifact_collection(format))

      response = user_request(:post, path, slug: slug, body: { delete_all: true })

      # The 202 is the whole outcome: no body, no job handle, so there is nothing to hand back.
      # Another 2xx is contract drift rather than an acceptance, so refuse it instead of reading
      # it as one, which matters most here because this route addresses the whole collection.
      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # @return [void]
    def delete_manifest(slug:, repository_name:, format:, image_id:, digest:)
      guard_format!(format, IMAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, image_id: image_id, digest: digest)

      path = manifest_path(slug, repository_name, format, image_id, digest)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # @return [void]
    def delete_container_tag(slug:, repository_name:, format:, image_id:, tag_name:)
      guard_format!(format, IMAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, image_id: image_id, tag_name: tag_name)

      path = sub_collection_member_path(slug, repository_name, format, 'images', image_id, 'tags', tag_name)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # @return [void]
    def delete_artifact(slug:, repository_name:, format:, id:)
      guard_format!(format, ARTIFACT_FORMATS)
      # Guarded here rather than resolved to a not-found the way the reads do: without this an
      # id-less delete would silently build a path with an empty final segment.
      guard_segments!(slug: slug, repository_name: repository_name, id: id)

      path = artifact_path(slug, repository_name, format, artifact_collection(format), id)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # Both this and #delete_file inherit RETRY_OPTIONS' connection-wide :delete exclusion, so
    # neither DELETE is replayed onto the row a first attempt already removed.
    #
    # @return [void]
    def delete_version(slug:, repository_name:, format:, version_id:)
      guard_format!(format, PACKAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, version_id: version_id)

      path = artifact_path(slug, repository_name, format, 'versions', version_id)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # @return [void]
    def delete_file(slug:, repository_name:, format:, file_id:)
      guard_format!(format, PACKAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, file_id: file_id)

      path = artifact_path(slug, repository_name, format, 'files', file_id)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # @return [void]
    def delete_npm_dist_tag(slug:, repository_name:, tag_id:)
      guard_segments!(slug: slug, repository_name: repository_name, tag_id: tag_id)

      path = artifact_path(slug, repository_name, 'npm', 'tags', tag_id)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    def dissociate_upstream_repository(slug:, repository_name:, format:, association_id:)
      guard_format!(format, ARTIFACT_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, association_id: association_id)

      upstream_repository_path = artifact_path(slug, repository_name, format, 'upstream_repositories', association_id)

      response = user_request(:delete, upstream_repository_path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 204

      true
    rescue ApiError => e
      if e.status == 404 && e.code == 'not_found'
        log_error(e, method: :delete, code: e.code, slug: slug, path: upstream_repository_path)
        return true
      end

      raise
    end

    def test_upstream_connection(slug:, name:)
      guard_segments!(slug: slug, name: name)

      response = user_request(:post, repository_test_path(slug, name), slug: slug)
      attributes = success_body(response, expected: Hash, slug: slug)

      raise_unexpected_success(response, slug: slug) if missing_verdict?(attributes)

      ConnectionTestResult.new(attributes)
    end

    def test_namespace_upstream_connection(slug:, format:, url:, credentials: nil)
      guard_format!(format, ARTIFACT_FORMATS)
      guard_segments!(slug: slug)
      guard_present!(url: url)

      body = { format: format, url: url, credentials: credentials }.compact
      response = user_request(:post, connection_test_path(slug), slug: slug, body: body)
      attributes = success_body(response, expected: Hash, slug: slug)

      raise_unexpected_success(response, slug: slug) if missing_verdict?(attributes)

      NamespaceConnectionTestResult.new(attributes)
    end

    # Batch repository membership check on the service-facing GitLab API
    # surface: does every repository id belong to the namespace? Returns the
    # ids that do not belong ([] means the whole batch does). AR never says why
    # an id failed, so an unknown id and one owned elsewhere are
    # indistinguishable. Any other failure raises, and the caller must fail
    # closed: an outage is not a verdict.
    #
    # @param namespace_id [String] canonical lowercase UUID of the AR namespace
    # @param repository_ids [Array<String>] 1..1000 canonical lowercase UUIDs
    # @return [Array<String>] the submitted ids that failed verification
    def verify_repositories(namespace_id:, repository_ids:)
      guard_verification_input!(namespace_id, repository_ids)

      response = service_request(:post, verifications_path(namespace_id),
        body: { repository_ids: repository_ids }, uuid: namespace_id)

      # The endpoint answers 204 and nothing else when every id belongs, so the
      # status is the whole verdict and there is no body to read. Another 2xx is
      # contract drift rather than an answer, so refuse it instead of reading it
      # as an all-belong verdict.
      raise_unexpected_verification_status(response, namespace_id) unless response.status == 204

      []
    rescue ApiError => e
      raise unless e.status == 422

      verification_failure_ids(e, repository_ids)
    end

    private

    def reporter
      # Scrub the credential this client actually transmits, so an injected
      # service credential is redacted rather than an independently re-resolved
      # one. The per-user bearer is already matched by the bearer pattern.
      ErrorReporter.new(service_token: @service_credential&.token)
    rescue AuthorizationError
      ErrorReporter.new
    end
    strong_memoize_attr :reporter

    def guard_format!(format, allowed)
      raise ArgumentError, "format must be one of: #{allowed.join(', ')}" if allowed.exclude?(format)
    end

    # Second line of defense behind guard_format!, so a format added to PACKAGE_FORMATS without a
    # class here raises the name of the miss, rather than reaching `row_class.new` as nil.
    def package_class(format)
      case format
      when 'maven' then MavenPackage
      when 'npm' then NpmPackage
      else raise ArgumentError, "format must be one of: #{PACKAGE_FORMATS.join(', ')}"
      end
    end

    # The AR file resource is structurally discriminated by format: only a Maven file carries
    # the sha1/sha512/md5 checksum trio. Guarded the same way package_class is.
    def file_class(format)
      case format
      when 'maven' then MavenFile
      when 'npm' then NpmFile
      else raise ArgumentError, "format must be one of: #{PACKAGE_FORMATS.join(', ')}"
      end
    end

    # Second line of defense behind guard_format!, so a format added to either list without a
    # collection here raises the name of the miss, rather than composing a path with an empty segment.
    def artifact_collection(format)
      case format
      when *PACKAGE_FORMATS then 'packages'
      when *IMAGE_FORMATS then 'images'
      else raise ArgumentError, "format must be one of: #{ARTIFACT_FORMATS.join(', ')}"
      end
    end

    # Reports a 404 as an absence rather than raising. Pass log: true where an unresolvable path is
    # not an ordinary outcome for the caller, so the drift behind it stays diagnosable.
    def nil_on_missing(log: false, **log_context)
      yield
    rescue ApiError => e
      raise unless e.status == 404

      log_error(e, **log_context) if log

      nil
    end

    def artifact(slug:, repository_name:, format:, collection:, id:, row_class:)
      guard_segments!(slug: slug, repository_name: repository_name)
      return if malformed_deep_link?(id)

      path = artifact_path(slug, repository_name, format, collection, id)

      # No log: a 404 here is the ordinary not-found outcome for a user-supplied id.
      nil_on_missing do
        response = user_request(:get, path, slug: slug)
        attributes = success_body(response, expected: Hash, slug: slug)

        # A body without an id is a serialization fault, not a present artifact whose readers are nil.
        raise_unexpected_success(response, slug: slug) if attributes['id'].blank?

        row_class.new(attributes)
      end
    end

    # rubocop:disable Metrics/ParameterLists -- one shared reader for every keyset list; each keyword names a distinct part of the request
    def artifact_page(
      slug:, repository_name:, format:, collection:, row_class:, limit:, cursor:,
      id: nil, sub_collection: nil, extra_query: {}, log_context: {})
      guard_segments!(slug: slug, repository_name: repository_name)
      # A sub-collection read needs its parent id, so guard it here rather than trust each caller:
      # without this an id-less call would silently build a `.../packages//versions` path.
      guard_segments!(id: id) if sub_collection

      query = extra_query.merge(limit: limit, cursor: cursor).compact
      path =
        if sub_collection
          sub_collection_path(slug, repository_name, format, collection, id, sub_collection)
        else
          artifacts_path(slug, repository_name, format, collection)
        end

      nil_on_missing(log: true, slug: slug, **log_context) do
        response = user_request(:get, path, slug: slug, query: query)
        attributes_list = success_body(response, expected: Array, slug: slug)
        raise_unexpected_success(response, slug: slug) unless attributes_list.all?(Hash)

        cursors = link_cursors(response, slug: slug)

        Page.new(
          nodes: attributes_list.map { |attributes| row_class.new(attributes) },
          next_cursor: cursors[:next],
          prev_cursor: cursors[:prev]
        )
      end
    end
    # rubocop:enable Metrics/ParameterLists

    # Sends no body, not an empty object: AR's EmptyObject schema 400s any body
    # field, so sending nothing keeps a later argument from silently riding along.
    def namespace_condition(uuid, action)
      guard_segments!(uuid: uuid)

      response = service_request(:post, namespace_condition_path(uuid, action), uuid: uuid)
      attributes = success_body(response, expected: Hash, uuid: uuid)

      # A hollow namespace would read as a successful transition.
      raise_unexpected_success(response, uuid: uuid) if attributes['id'].blank?

      Namespace.new(attributes)
    end

    # Per-user entry point: owns TokenExchange#token_for.
    def user_request(http_method, path, slug:, query: nil, body: nil)
      authed_request(http_method, path, form: BEARER_FORM, query: query, body: body, slug: slug) do
        # A missing user is a wiring fault, not a credential outcome: raising the
        # same error the exchange does would render it to the caller as an AR
        # outage.
        raise ArgumentError, 'current_user is required for a per-user request' if @current_user.nil?

        @token_exchange.token_for(@current_user, @organization)
      end
    end

    # Service entry point: owns ServiceCredential#token, no user, no slug.
    def service_request(http_method, path, query: nil, body: nil, **attribution)
      authed_request(http_method, path, form: SERVICE_TOKEN_FORM, query: query, body: body, **attribution) do
        @service_credential.token
      end
    end

    # The blank guard tests the bare credential, not the composed header: a
    # prefix alone would make it non-blank and stop it failing closed.
    def authed_request(http_method, path, form:, query: nil, body: nil, **attribution)
      guard_transport!

      token = yield
      raise_missing_credential if token.blank?

      credential_header = { form[:header] => "#{form[:prefix]}#{token}" }

      perform_request(http_method, path, credential_header, query: query, body: body, **attribution)
    end

    def perform_request(http_method, path, credential_header, query: nil, body: nil, **attribution)
      response = connection.run_request(http_method, path, body, nil) do |req|
        req.params.update(query) if query.present?
        req.headers.update(credential_header)

        correlation_id = resolve_correlation_id
        req.headers['X-Request-Id'] = correlation_id if correlation_id.present?
      end

      handle_response(response, http_method, **attribution)
    rescue ::Faraday::ParsingError => e
      status = e.response_status
      raise ApiError.new(status: 404) if status == 404

      message = 'Artifact Registry returned an unreadable response'
      raise AuthorizationError.new(message, status: status) if [401, 403].include?(status)

      raise_terminal(UnavailableError, message, http_method, status: status, cause: e, **attribution)
    rescue ::Faraday::SSLError => e
      raise_terminal(UnavailableError, "Artifact Registry TLS connection failed: #{e.message}",
        http_method, cause: e, **attribution)
    rescue ::Faraday::Error => e
      raise_terminal(UnavailableError, 'Artifact Registry request failed', http_method, cause: e, **attribution)
    end

    def handle_response(response, http_method, **attribution)
      status = response.status

      return response if (200..299).cover?(status)

      raise_error(status, response, http_method, **attribution)
    end

    def success_body(response, expected:, **attribution)
      body = response.body
      return body if body.is_a?(expected)

      raise_unexpected_success(response, **attribution)
    end

    # `repositories` is always an array, `[]` when empty, so a missing key and a
    # value that is not an array of objects both violate the contract, and
    # list_class is what tells those two apart once body_class reports Hash.
    def repository_list(response, slug:)
      body = success_body(response, expected: Hash, slug: slug)
      list = body['repositories']

      unless list.is_a?(Array) && list.all?(Hash)
        raise_unexpected_success(response, slug: slug, list_class: list.class.name)
      end

      [list, body['permissions']]
    end

    def permissions_query(include_permissions)
      include_permissions ? { include_permissions: true } : {}
    end

    def repository_with_verdicts(attributes, read:, slug:, requested:)
      Repository.new(attributes,
        verdicts(attributes['permissions'], scope: :repository, read: read, slug: slug, requested: requested))
    end

    def verdicts(permissions, scope:, read:, slug:, requested:)
      return unless requested
      return Permissions::Verdicts.absent(scope: scope, read: read, slug: slug) unless permissions.is_a?(Hash)

      Permissions::Verdicts.new(permissions, scope: scope, read: read, slug: slug)
    end

    def missing_verdict?(attributes)
      attributes['passed'].nil?
    end

    # Refuses only a body missing an expected key, not one whose value is null: a present key
    # passes through so the reader, not this guard, decides what a null value means.
    def missing_expected_keys?(attributes, *expected_keys)
      expected_keys.any? { |key| !attributes.key?(key) }
    end

    def raise_unexpected_success(response, **attribution)
      raise_terminal(
        UnavailableError,
        'Artifact Registry returned an unexpected success response',
        response.env&.method,
        status: response.status,
        body_class: response.body.class.name,
        **attribution
      )
    end

    def link_cursors(response, slug:)
      header = response.headers['Link']
      links = Gitlab::Utils::LinkHeaderParser.new(header).parse

      # Reading the header rather than each URI keeps the last page quiet: it still carries rel="prev".
      if header.present? && !links.keys.intersect?(PAGINATION_RELS)
        log_error(Error.new('Artifact Registry Link header yielded no usable rels'), slug: slug)
      end

      PAGINATION_RELS.index_with { |direction| link_cursor(links.dig(direction, :uri), direction, slug: slug) }
    rescue URI::InvalidURIError => e
      log_error(e, slug: slug)
      PAGINATION_RELS.index_with(nil)
    end

    def link_cursor(uri, direction, slug:)
      return unless uri

      cursor = Rack::Utils.parse_query(uri.query)['cursor']
      return cursor if cursor.present?

      log_error(Error.new("Artifact Registry #{direction} link carries no cursor"), slug: slug)
      nil
    end

    # The slug or uuid is what makes an entry attributable to a namespace, so
    # whichever the caller holds is logged alongside the request identifiers.
    def log_error(error, **context)
      reporter.log(error, {
        url: @base_url,
        correlation_id: resolve_correlation_id,
        status: error.try(:status),
        request_id: error.try(:request_id),
        **context
      }.compact)
    end

    def raise_missing_credential
      raise AuthorizationError, 'No Artifact Registry credential was obtained'
    end

    # Single terminal entry point. The cause is passed explicitly rather than
    # left to Ruby's implicit chaining, so the raised error always carries the
    # original transport failure (or nil) and never a reporting-side exception.
    def raise_terminal(error_class, message, http_method, cause: nil, **context)
      error = reporter.report_terminal(
        error_class: error_class, message: message, url: @base_url, method: http_method,
        correlation_id: resolve_correlation_id, **context
      )
      raise error, error.message, cause: cause
    end

    def raise_error(status, response, http_method, **attribution)
      envelope = error_envelope(response)
      message = envelope[:message]
      request_id = envelope[:request_id] || header_request_id(response)

      case status
      when 401, 403
        raise AuthorizationError.new(message, status: status, request_id: request_id)
      when 429, 500..599
        raise_terminal(UnavailableError, message, http_method,
          status: status, request_id: request_id, code: envelope[:code], **attribution)
      else
        raise ApiError.new(
          message, status: status, code: envelope[:code], request_id: request_id, details: envelope[:details]
        )
      end
    end

    def error_envelope(response)
      body = response.body
      error = body['error'] if body.is_a?(Hash)

      return { code: nil, message: redacted_snippet(error), request_id: nil } if error.is_a?(String)
      return error_snippet_envelope(body) unless error.is_a?(Hash)

      {
        code: redacted_snippet(error['code'].to_s),
        message: redacted_snippet(error['message'].to_s),
        request_id: redacted_snippet(error['request_id'].to_s),
        # Structured, machine-readable failure data (e.g. the verification
        # endpoint's failing repository ids). Only allowlisted shapes are
        # carried: details bypasses the snippet redaction, so anything an AR
        # error might place there beyond known caller-supplied ids is dropped.
        details: allowlisted_details(error['details'])
      }
    end

    def error_snippet_envelope(body)
      snippet =
        case body
        when String then redacted_snippet(body)
        when Hash then redacted_snippet(body.values_at(*ERROR_SNIPPET_KEYS).grep(String).join(' '))
        end

      { code: nil, message: snippet, request_id: nil }
    end

    def namespaces_path
      NAMESPACES_PATH
    end

    def namespace_path(uuid)
      "#{namespaces_path}/#{encode_segment(uuid)}"
    end

    def namespace_condition_path(uuid, action)
      "#{namespace_path(uuid)}/#{encode_segment(action)}"
    end

    def resolve_correlation_id
      Labkit::Correlation::CorrelationId.current_id
    end

    # AR-supplied like the envelope, so it gets the same bounded redaction: an
    # intermediary echoing a credential here would otherwise reach both the log
    # context and the GraphQL error extensions.
    def header_request_id(response)
      redacted_snippet(response.headers['X-Request-Id'])
    end

    def redacted_snippet(text)
      reporter.snippet(text)
    end

    def repositories_path(slug)
      "#{API_VERSION}/#{encode_segment(slug)}/repositories"
    end

    def namespace_statistics_path(slug)
      "#{API_VERSION}/#{encode_segment(slug)}/statistics"
    end

    def verifications_path(namespace_id)
      "#{namespace_path(namespace_id)}/repositories/verifications"
    end

    # Programmer-error guards: a well-behaved caller validates and canonicalizes
    # ids before reaching here. The two arguments carry different rules on
    # purpose. namespace_id is only ever spent on this AR URL, so it is held to
    # what AR itself accepts, any canonical UUID. repository_ids are also written
    # to IAM afterwards, whose proto CEL regex accepts UUIDv7 alone, so they stay
    # on the stricter rule the caller already applied.
    def guard_verification_input!(namespace_id, repository_ids)
      raise ArgumentError, 'namespace_id must be a canonical UUID' unless canonical_uuid?(namespace_id)

      unless repository_ids.is_a?(Array) && repository_ids.size.between?(1, MAX_VERIFICATION_BATCH)
        raise ArgumentError, "repository_ids must carry between 1 and #{MAX_VERIFICATION_BATCH} ids"
      end

      return if repository_ids.all? { |id| ::Gitlab::UUID.v7?(id) }

      raise ArgumentError, 'repository_ids must be canonical UUIDv7s'
    end

    # Mirrors AR's own parseCanonicalUUID, which parses the value and rejects it
    # unless it round-trips through the lowercase canonical form. UUID_REGEX
    # alone is not enough: \h matches uppercase hex, which AR answers with a 400.
    def canonical_uuid?(value)
      value.is_a?(String) && value.match?(UUID_REGEX) && value == value.downcase
    end

    # Allowlist of the structured error details the client carries. Only the
    # shapes a consumer actually reads pass through: the verification endpoint's
    # failing repository ids, and the manifest delete 409's blocking parent
    # digests. Each key carries its own element predicate, since a digest is not
    # an id. A future consumer extends this consciously rather than inheriting
    # an unredacted passthrough.
    def allowlisted_details(details)
      return unless details.is_a?(Hash)

      {
        'repository_ids' => allowlisted_repository_ids(details['repository_ids']),
        'parents' => allowlisted_parent_digests(details['parents'])
      }.compact.presence
    end

    def allowlisted_repository_ids(ids)
      return unless carried_list?(ids) && ids.all? { |id| ::Gitlab::UUID.v7?(id) }

      ids
    end

    def allowlisted_parent_digests(digests)
      return unless carried_list?(digests)
      return digests if digests.all? { |digest| digest.match?(DIGEST_SHAPE_REGEX) }

      # Dropped whole rather than filtered: a short list reads as the complete set of
      # blockers, so the caller would clear it and meet the same refusal.
      log_error(Error.new("Artifact Registry sent #{digests.size} parent digests, not all of the digest shape"))

      nil
    end

    def carried_list?(values)
      values.is_a?(Array) && values.present? && values.all?(String)
    end

    # A 422 is the endpoint's "these ids do not belong" verdict, with the
    # failing ids echoed under details['repository_ids'] (allowlisted in
    # error_envelope). A 422 whose details carry no failing ids breaks that
    # contract, so it is escalated as an unusable answer rather than a verdict.
    # Held to the ids the caller actually submitted, so a bug on the AR side
    # cannot widen the verdict to a resource this request never named. ADR-009
    # has AR echo the failing ids deduplicated in submitted order, so against a
    # correct response the intersection changes nothing.
    def verification_failure_ids(error, submitted)
      details = error.details.is_a?(Hash) ? error.details['repository_ids'] : nil
      failing_ids = details.is_a?(Array) ? details & submitted : nil

      # An empty intersection is not "every id belongs": a 422 says at least one
      # failed, so a response naming none of the submitted ids is unreadable and
      # must not read as a pass.
      raise_unexpected_verification_failure(error) if failing_ids.blank?

      failing_ids
    end

    def raise_unexpected_verification_status(response, namespace_id)
      raise_terminal(
        UnavailableError,
        'Artifact Registry answered repository verification with an unexpected status',
        :post,
        status: response.status, uuid: namespace_id
      )
    end

    def raise_unexpected_verification_failure(error)
      raise_terminal(
        UnavailableError,
        'Artifact Registry returned an unreadable verification failure',
        :post,
        status: error.status, code: error.code, request_id: error.request_id
      )
    end

    def repository_path(slug, name)
      "#{repositories_path(slug)}/#{encode_segment(name)}"
    end

    def repository_test_path(slug, name)
      "#{repository_path(slug, name)}/test"
    end

    def connection_test_path(slug)
      "#{API_VERSION}/#{encode_segment(slug)}/connection_test"
    end

    def namespace_details_path(slug)
      "#{API_VERSION}/#{encode_segment(slug)}/namespace"
    end

    def artifacts_path(slug, repository_name, format, collection)
      "#{repository_path(slug, repository_name)}/#{encode_segment(format)}/#{collection}"
    end

    def artifact_path(slug, repository_name, format, collection, id)
      "#{artifacts_path(slug, repository_name, format, collection)}/#{encode_segment(id)}"
    end

    def sub_collection_path(slug, repository_name, format, collection, id, sub_collection)
      "#{artifacts_path(slug, repository_name, format, collection)}/#{encode_segment(id)}/#{sub_collection}"
    end

    def sub_collection_member_path(slug, repository_name, format, collection, id, sub_collection, member_id)
      path = sub_collection_path(slug, repository_name, format, collection, id, sub_collection)

      "#{path}/#{encode_segment(member_id)}"
    end

    # The manifest member path, keyed on the image id and the digest, shared by the reads that
    # address a single manifest and by the delete.
    def manifest_path(slug, repository_name, format, image_id, digest)
      sub_collection_member_path(slug, repository_name, format, 'images', image_id, 'manifests', digest)
    end

    def bulk_delete_path(slug, repository_name, format, collection)
      "#{artifacts_path(slug, repository_name, format, collection)}/bulk_delete"
    end

    def encode_segment(value)
      ERB::Util.url_encode(value.to_s)
    end

    def provided_fields(**fields)
      fields.reject { |_field, value| value.equal?(NOT_PROVIDED) }
    end

    def guard_present!(**fields)
      fields.each do |field, value|
        # NOT_PROVIDED is a plain object, so blank? alone lets the sentinel through.
        raise ArgumentError, "#{field} is required" if value.blank? || value.equal?(NOT_PROVIDED)
      end
    end

    def guard_segments!(**segments)
      guard_present!(**segments)

      segments.each do |segment, value|
        raise ArgumentError, "#{segment} must not be a bare '.' or '..' segment" if dot_segment?(value)
      end
    end

    def guard_uuid!(**fields)
      fields.each do |field, value|
        raise ArgumentError, "#{field} must be a UUID" unless value.to_s.match?(UUID_REGEX)
      end
    end

    def dot_segment?(value)
      value.to_s == '.' || value.to_s == '..'
    end

    # A user-supplied deep-link value that cannot address a resource. The single-artifact reads
    # resolve nil for one rather than raising, so a bad deep link returns the same not-found
    # outcome as a real 404 and exposes no id-syntax oracle -- unlike a blank structural segment,
    # which raises.
    def malformed_deep_link?(*values)
      values.any? { |value| value.blank? || dot_segment?(value) }
    end

    def connection
      @connection ||= Faraday.new(@base_url, headers: { user_agent: USER_AGENT },
        request: Gitlab::HTTP::DEFAULT_TIMEOUT_OPTIONS) do |conn|
        conn.options.params_encoder = Faraday::FlatParamsEncoder
        conn.request :json
        conn.response :json, content_type: 'application/json'
        conn.request :retry, RETRY_OPTIONS
        conn.request :gitlab_error_callback, error_callback_options
        conn.adapter :net_http
      end
    end

    # Per-attempt Faraday callback, sanitized: error tracking receives a fresh
    # same-class cause-free exception and the allowlisted context, never the raw
    # Faraday environment. Call count is retained (still max + 1 on a retried GET).
    def error_callback_options
      # A bound method keeps the per-attempt state resolved at call time rather
      # than captured when the connection is built.
      { callback: method(:report_attempt) }
    end

    # The failing path is what makes a per-attempt entry actionable, so it is
    # reported alongside the origin, redacted and bounded like any AR-supplied
    # value. The query string is dropped rather than redacted.
    def report_attempt(env, exception)
      reporter.report_attempt(exception, url: attempt_url(env), method: env[:method],
        correlation_id: resolve_correlation_id, status: env[:status])
    end

    def attempt_url(env)
      path = env[:url]&.path
      return @base_url if path.blank?

      redacted_snippet("#{@base_url.chomp('/')}#{path}")
    end

    # Userinfo, query and fragment are refused because this URL is logged
    # verbatim in error contexts. A path is refused because each method builds
    # its own absolute path, so a base path would be duplicated in the request.
    def validate_base_url!(base_url)
      violation = Configuration.base_url_violation(Addressable::URI.parse(base_url.to_s))

      raise ConfigurationError, violation if violation
    rescue Addressable::URI::InvalidURIError => e
      # The parser message embeds the offending URL and this error reaches API
      # callers through the resolver, so the host is logged rather than returned.
      reporter.log(e, { url: base_url })

      raise ConfigurationError, 'base_url is not a parseable URL'
    end

    # Both credential paths are held to HTTPS in production: the per-user path
    # carries a signed user JWT and, on writes, upstream credentials, the service
    # path the service token. Enforced in authed_request before any is minted.
    def guard_transport!
      return unless Rails.env.production?
      return unless Addressable::URI.parse(@base_url.to_s).scheme == 'http'

      raise ConfigurationError, 'base_url must be HTTPS in production for credential-authenticated requests'
    end
  end
end
