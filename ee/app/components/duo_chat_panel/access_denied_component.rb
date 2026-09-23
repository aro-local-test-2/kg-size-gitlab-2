# frozen_string_literal: true

module DuoChatPanel
  class AccessDeniedComponent < ViewComponent::Base
    def initialize(container:, user:)
      @container = container
      @user = user
    end

    private

    attr_reader :container, :user

    def data
      {
        testid: 'duo-chat-panel-access-denied',
        access_denied: true.to_s,
        container_type: container.type,
        auto_expand: 'false'
      }.compact
    end
  end
end
