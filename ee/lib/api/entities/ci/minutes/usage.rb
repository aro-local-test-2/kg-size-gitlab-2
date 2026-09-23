# frozen_string_literal: true

module API
  module Entities
    module Ci
      module Minutes
        class Usage < Grape::Entity
          expose :total_minutes_used, documentation: { type: 'Integer', example: 105 }
          expose :monthly_minutes_used, documentation: { type: 'Integer', example: 100 }
          expose :purchased_minutes_used, documentation: { type: 'Integer', example: 5 }
        end
      end
    end
  end
end
