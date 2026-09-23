# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::DateRange, feature_category: :audit_events do
  concern = described_class

  controller(ActionController::Base) do
    # `described_class` is not available in this context
    include concern

    def index
      head :ok
    end
  end

  around do |example|
    travel_to(Time.zone.parse('2024-06-15 09:00:00')) { example.run }
  end

  before do
    routes.draw { get 'index' => 'anonymous#index' }
  end

  def created_after
    controller.params[:created_after]
  end

  def created_before
    controller.params[:created_before]
  end

  describe '#set_date_range' do
    it 'defaults to the start of the current month through the end of today', :aggregate_failures do
      get :index, format: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(created_after).to eq(Date.new(2024, 6, 1))
      expect(created_before).to eq(Date.new(2024, 6, 15).end_of_day)
    end

    it 'keeps the given created_after and extends created_before to the end of its day', :aggregate_failures do
      get :index, params: { created_after: '2024-06-05', created_before: '2024-06-10' }, format: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(created_after).to eq('2024-06-05')
      expect(created_before).to eq(Date.new(2024, 6, 10).end_of_day)
    end
  end

  describe '#validate_date_range' do
    it 'accepts a range exactly at the limit' do
      get :index, params: { created_after: '2024-05-15', created_before: '2024-06-15' }, format: :json

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'rejects a range longer than the limit' do
      get :index, params: { created_after: '2024-05-14', created_before: '2024-06-15' }, format: :json

      expect(response).to have_gitlab_http_status(:bad_request)
    end
  end
end
