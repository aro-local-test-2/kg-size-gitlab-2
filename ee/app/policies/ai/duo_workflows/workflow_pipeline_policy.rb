# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class WorkflowPipelinePolicy < BasePolicy
      delegate { @subject.workflow }
    end
  end
end
