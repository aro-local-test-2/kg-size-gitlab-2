# frozen_string_literal: true

# Wires the Policy Store facade (gems/gitlab-policy-store) to its persistent
# ActiveRecord backend. This file ships only in EE, so FOSS keeps the gem's
# inert in-memory default.
Rails.application.config.to_prepare do
  Gitlab::PolicyStore.configure do |config|
    config.repository = Govern::PolicyStore::ActiveRecordPolicyRepository.new
    config.evaluation_recorder = Govern::PolicyStore::ActiveRecordEvaluationRecorder.new
  end
end
