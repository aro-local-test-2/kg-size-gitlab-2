# frozen_string_literal: true

module Gitlab
  module Duo
    module RiskClassification
      # Runs every registered signal against a merge request.
      #
      # Extraction degrades rather than fails. A signal that reports itself
      # unavailable, or that raises, is recorded in `missing` and lowers the
      # assessment's confidence -- it never silently contributes zero, because
      # "we could not measure this" and "this looks safe" must not be
      # indistinguishable to the scoring function.
      class SignalsExtractor
        include ExtractorsRegistry

        # `signals` and `mitigations` both map "<signal>.<dimension>" to a
        # normalized 0..1 value; they are separate because a mitigation has to
        # subtract from the score rather than add to it. `missing` names the
        # signals that could not be measured, from either channel.
        Result = Struct.new(:signals, :mitigations, :missing, keyword_init: true)

        # Order is presentation only; contributions are set by the scoring
        # function, not by position here.
        register_extractor(Signals::DiffShape)
        register_extractor(Signals::TestCoverage)
        register_extractor(Signals::TestEvidence)
        register_extractor(Signals::AiAuthorship)
        register_extractor(Signals::DependencyManifest)
        register_extractor(Signals::Ownership)
        register_extractor(Signals::AuthorExperience)
        register_extractor(Signals::Reversibility)
        register_extractor(Signals::RolloutGuard)
        register_extractor(Signals::Revert)

        # Looks up a registered signal class by its `signal_name`, so GraphQL
        # can resolve a label for a "<signal>.<dimension>" or bare signal key
        # without the caller needing its own copy of the registry.
        def self.signal_class_for(name)
          registered_extractors.find { |signal_class| signal_class.signal_name == name.to_s }
        end

        # Translated label for a `signal_breakdown`/`missing_signals` key.
        # `key` is either a bare signal name (e.g. "diff_shape") or a
        # "<signal>.<dimension>" pair (e.g. "diff_shape.churn"). Returns nil
        # for claim keys, which have no registered signal class yet.
        def self.label_for(key)
          name, dimension = key.to_s.split('.', 2)
          signal_class = signal_class_for(name)
          return unless signal_class

          dimension ? signal_class.dimensions[dimension.to_sym]&.label : signal_class.label
        end

        def initialize(merge_request)
          @merge_request = merge_request
        end

        def execute
          signals = {}
          mitigations = {}
          missing = []

          registered_extractors.each do |signal_class|
            extracted = extract_signal(signal_class)

            if extracted.nil?
              missing << signal_class.signal_name
            else
              channel = signal_class.mitigation? ? mitigations : signals
              channel.merge!(namespaced(signal_class, extracted))
            end
          end

          Result.new(signals: signals, mitigations: mitigations, missing: missing)
        end

        private

        attr_reader :merge_request

        def extract_signal(signal_class)
          signal = signal_class.new(merge_request)
          return unless signal.available?

          signal.extract
        rescue StandardError => error
          # One broken extractor must not cost us the whole assessment.
          ::Gitlab::ErrorTracking.track_exception(
            error,
            merge_request_id: merge_request.id,
            signal: signal_class.signal_name
          )

          nil
        end

        def namespaced(signal_class, extracted)
          extracted.transform_keys { |key| :"#{signal_class.signal_name}.#{key}" }
        end
      end
    end
  end
end
