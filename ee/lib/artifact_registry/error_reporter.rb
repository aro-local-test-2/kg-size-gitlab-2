# frozen_string_literal: true

module ArtifactRegistry
  # Owns every surface an AR client error reaches error tracking through: the
  # allowlisted context, credential redaction, and the exception copy the logger
  # is free to mutate. Centralizing them is what keeps a credential out of a
  # report, whether it would arrive in a message, a context value, or a Faraday
  # environment.
  class ErrorReporter
    REDACTED_VALUE = '[REDACTED]'
    BEARER_CREDENTIAL_PATTERN = /(bearer\s+)\S+/i
    # A three-segment token with 16+ base64url chars per segment: the JWT shape,
    # long enough that ordinary dotted content (filenames, versions, hostnames)
    # cannot reach it. Shorter dotted tokens are redacted only when they arrive
    # as the client's own credential or behind Bearer, not by shape.
    JWT_PATTERN = /[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}/

    MAX_SNIPPET = 200

    # Every key any report surface may carry. A caller cannot widen this, so a
    # future context key holding a credential cannot reach error tracking
    # without being added here deliberately.
    # digest is a content-addressable manifest hash, not a credential, so a manifest read can log
    # it alongside id to say which of the two drifted on a 404.
    ALLOWED_CONTEXT_KEYS = %i[
      url path method status code request_id slug uuid id digest body_class list_class correlation_id
    ].freeze

    # service_token is the bare credential the client transmits, scrubbed from
    # messages by exact match because its shape is not guaranteed to match a
    # pattern. AR echoes it either as-sent or percent-encoded, so both forms are
    # precomputed once here (the token never changes) and deduplicated.
    def initialize(service_token: nil)
      @service_token_forms = token_forms(service_token.presence)
    end

    # Reports the terminal outcome once and returns a fresh operational exception
    # for the client to raise with an explicit cause.
    def report_terminal(error_class:, message:, url:, method:, correlation_id:, **context)
      allowed = build_context(url: url, method: method, correlation_id: correlation_id, **context)
      error = build_exception(error_class, redact(message), context)

      # A copy, because ErrorTracking#process_exception calls set_backtrace on an
      # exception that has none: logging the instance the client is about to raise
      # would overwrite the caller's backtrace with this frame.
      Gitlab::ErrorTracking.log_exception(error.dup, allowed)

      error
    end

    # Replaces the per-attempt Faraday error callback. The original exception is
    # reported with its message redacted, so error tracking keeps the adapter
    # backtrace while a credential in the message cannot survive.
    def report_attempt(exception, url:, method:, correlation_id:, **context)
      allowed = build_context(url: url, method: method, correlation_id: correlation_id, **context)

      Gitlab::ErrorTracking.log_exception(redacted_exception(exception), allowed)
    end

    # Direct log for outcomes whose context the caller assembles, such as the
    # namespace 404 and the link-parse diagnostics. The context is held to the
    # same allowlist, and the message redacted, because an AR-supplied value can
    # reach these exceptions too.
    def log(exception, context)
      Gitlab::ErrorTracking.log_exception(redacted_exception(exception), allowed_context(context))
    end

    def redact(text)
      scrub_service_token(text.to_s)
        .gsub(BEARER_CREDENTIAL_PATTERN, "\\1#{REDACTED_VALUE}")
        .gsub(JWT_PATTERN, REDACTED_VALUE)
    end

    # Redacted, bounded form of an AR-supplied value: a response body for an
    # exception message, or a header echoed back into one.
    def snippet(text)
      redact(text).strip.presence&.truncate(MAX_SNIPPET)
    end

    private

    # The raw token plus its percent-encoded form: AR echoes the credential
    # either as-sent or percent-encoded. url_encode output is pure ASCII, so no
    # encoding merge can raise here.
    def token_forms(token)
      return [] unless token

      [token, ERB::Util.url_encode(token)].uniq
    end

    # Scrubs each token form on the message only, so a first-party encoded URL
    # path in the text is left intact rather than rewritten.
    def scrub_service_token(text)
      @service_token_forms.reduce(text) { |scrubbed, form| scrubbed.gsub(form, REDACTED_VALUE) }
    end

    def build_context(url:, method:, correlation_id:, **context)
      allowed_context(context.merge(url: url, method: method, correlation_id: correlation_id))
    end

    def allowed_context(context)
      context.slice(*ALLOWED_CONTEXT_KEYS).compact.freeze
    end

    def build_exception(error_class, message, context)
      error_class.new(message, **context.slice(:status, :request_id))
    end

    # Same class, attributes and backtrace, redacted message: the logger keeps a
    # usable stack and the typed fields a reader needs, without a credential
    # travelling in the text. Errors outside this hierarchy take a message-only
    # copy, since their constructors are unknown.
    def redacted_exception(exception)
      message = redact(exception.message.to_s)

      redacted = rebuild(exception, message)
      redacted.set_backtrace(exception.backtrace) if exception.backtrace

      redacted
    end

    def rebuild(exception, message)
      return exception.class.new(message) unless exception.is_a?(Client::Error)

      exception.class.new(message, **typed_attributes(exception))
    end

    def typed_attributes(exception)
      attributes = { status: exception.status, request_id: exception.request_id }
      attributes[:code] = exception.code if exception.respond_to?(:code)

      attributes.compact
    end
  end
end
