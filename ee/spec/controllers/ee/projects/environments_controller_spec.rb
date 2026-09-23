# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::EnvironmentsController, feature_category: :continuous_delivery do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, maintainers: user) }

  let_it_be(:environment) do
    create(:environment, name: 'production', project: project)
  end

  before do
    sign_in(user)
  end

  describe '#GET terminal' do
    let(:protected_environment) { create(:protected_environment, name: environment.name, project: project) }

    before do
      allow(License).to receive(:feature_available?).and_call_original
      allow(License).to receive(:feature_available?).with(:protected_environments).and_return(true)
    end

    context 'when environment is protected' do
      context 'when user does not have access to it' do
        before do
          protected_environment

          get :terminal, params: environment_params
        end

        it 'responds with access denied' do
          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when user has access to it' do
        before do
          protected_environment.deploy_access_levels.create!(user: user)

          get :terminal, params: environment_params
        end

        it 'is successful' do
          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end

    context 'when environment is not protected' do
      it 'is successful' do
        get :terminal, params: environment_params

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end

  describe '#GET terminal_websocket_authorize' do
    let(:protected_environment) { create(:protected_environment, name: environment.name, project: project) }

    before do
      allow(License).to receive(:feature_available?).and_call_original
      allow(License).to receive(:feature_available?).with(:protected_environments).and_return(true)
      allow(Gitlab::Workhorse).to receive(:verify_api_request!).and_return(nil)

      # `environment` is a let_it_be object shared across the examples below, so
      # clear its memoized protection state before each one to avoid an earlier
      # example's result leaking into a later one.
      environment.clear_memoization(:associated_protected_environments)

      # A real terminal must exist so a 404 here can only mean the
      # request was denied, not that there was simply nothing to connect to.
      # Stub the controller's own memoized finder instead of the environment
      # record itself, since `.find` builds a separate AR instance each call.
      allow(controller).to receive(:environment).and_return(environment)
      allow(environment).to receive(:terminals).and_return([:fake_terminal])
      allow(Gitlab::Workhorse).to receive(:channel_websocket).with(:fake_terminal).and_return(workhorse: :response)
    end

    context 'when environment is protected' do
      context 'when user does not have access to it' do
        before do
          protected_environment

          get :terminal_websocket_authorize, params: environment_params
        end

        it 'responds with access denied' do
          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when user has access to it' do
        before do
          protected_environment.deploy_access_levels.create!(user: user)

          get :terminal_websocket_authorize, params: environment_params
        end

        it 'is successful' do
          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end

    context 'when environment is not protected' do
      it 'is successful' do
        get :terminal_websocket_authorize, params: environment_params

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end

  describe 'POST #cancel_auto_stop' do
    subject { post :cancel_auto_stop, params: params }

    let(:params) { environment_params }

    context 'when environment is set as auto-stop' do
      let_it_be_with_reload(:environment) { create(:environment, :will_auto_stop, name: 'staging', project: project) }

      it_behaves_like 'successful response for #cancel_auto_stop'

      context 'when the environment is protected' do
        before do
          stub_licensed_features(protected_environments: true)
          create(:protected_environment, name: 'staging', project: project)
        end

        it 'shows not found' do
          subject

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end

  def environment_params(opts = {})
    opts.reverse_merge(namespace_id: project.namespace, project_id: project, id: environment.id)
  end
end
