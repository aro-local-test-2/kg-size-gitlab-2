# frozen_string_literal: true

# Ai::DuoWorkflows::CreateWorkflowService refuses a CI-backed flow (behind the
# duo_workflow_precondition_check flag, on by default in specs) when the project has no
# eligible gitlab--duo runner. Factory projects have none, so a spec that creates a workflow
# through that service (or its callers) and does not care about the check uses this to make
# the project look ready. It is inert until called, so specs that exercise the check itself
# are unaffected.
module DuoWorkflowPreconditionHelpers
  def stub_duo_runner_available(available = true)
    allow(::Ai::DuoWorkflow::ProjectReadiness).to receive(:new).and_return(
      instance_double(::Ai::DuoWorkflow::ProjectReadiness, runner_available?: available)
    )
  end
end

RSpec.configure do |config|
  config.include DuoWorkflowPreconditionHelpers
end
