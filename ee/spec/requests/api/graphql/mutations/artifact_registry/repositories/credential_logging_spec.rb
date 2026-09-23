# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository writes carrying upstream credentials',
  feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: current_organization).user }
  let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: current_organization) }

  let(:slug) { 'resolved-handle' }
  let(:namespace) do
    ArtifactRegistry::Namespace.new('id' => namespace_mapping.ar_namespace_id, 'slug' => slug, 'status' => 'active')
  end

  let(:client) { instance_double(ArtifactRegistry::Client) }

  let(:graphql_logger) { instance_double(Gitlab::GraphqlLogger) }
  let(:exception_logger) { instance_double(Gitlab::ErrorTracking::Logger) }
  let(:graphql_log) { [] }
  let(:exception_log) { [] }
  let(:request_log) { [] }

  let(:input) { base_input.merge('settings' => settings) }
  let(:mutation) { graphql_mutation(mutation_name, input) }

  before do
    current_organization.clear_memoization(:artifact_registry_client)
    allow(ArtifactRegistry::Client).to receive(:new).and_return(client)
    allow(client).to receive(:namespace).with(uuid: namespace_mapping.ar_namespace_id).and_return(namespace)
    allow(client).to receive(client_method).and_raise(StandardError, 'upstream write failed')

    allow(Gitlab::GraphqlLogger).to receive(:build).and_return(graphql_logger)
    allow(graphql_logger).to receive(:info) { |payload| graphql_log << payload }
    allow(Gitlab::ErrorTracking::Logger).to receive(:build).and_return(exception_logger)
    allow(exception_logger).to receive(:error) { |payload| exception_log << payload }
  end

  def post_mutation_capturing_request_log
    subscriber = ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*, payload|
      request_log << payload[:params]
    end

    post_graphql_mutation(mutation, current_user: current_user)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  where(:mutation_name, :client_method, :base_input) do
    :artifact_registry_repository_create | :create_repository |
      { 'name' => 'my-repo', 'format' => 'MAVEN', 'kind' => 'REMOTE' }
    :artifact_registry_repository_update | :update_repository | { 'name' => 'my-repo' }
  end

  with_them do
    where(:shape, :settings, :secrets) do
      'a username and password' |
        { 'url' => 'https://upstream.test',
          'credentials' => { 'username' => 'robot-user-9c1', 'password' => 'robot-pass-3f7' } } |
        %w[robot-user-9c1 robot-pass-3f7]
      'an npm auth token' |
        { 'url' => 'https://upstream.test', 'credentials' => { 'authToken' => 'npm-token-8d2' } } |
        %w[npm-token-8d2]
      'a URL carrying userinfo' |
        { 'url' => 'https://robot-user-9c1:robot-pass-3f7@upstream.test' } |
        %w[robot-user-9c1 robot-pass-3f7]
    end

    with_them do
      it 'keeps the credential out of the request log, the GraphQL variable log, and the exception log',
        :aggregate_failures do
        post_mutation_capturing_request_log

        expect(request_log).not_to be_empty
        expect(graphql_log).not_to be_empty
        expect(exception_log).not_to be_empty

        logged = (request_log + graphql_log + exception_log).map(&:to_s)

        secrets.each do |secret|
          expect(logged).to all(exclude(secret))
        end
        expect(graphql_log.map { |payload| payload[:variables].to_s }).to include(a_string_including('[FILTERED]'))
        expect(request_log.map(&:to_s)).to include(a_string_including('[FILTERED]'))
      end
    end
  end

  context 'when the client binds the settings object to a variable of its own' do
    let(:client_method) { :create_repository }
    let(:query) do
      <<~GQL
        mutation($name: String!, $s: ArtifactRegistryRemoteSettingsInput!) {
          artifactRegistryRepositoryCreate(input: { name: $name, format: MAVEN, kind: REMOTE, settings: $s }) {
            errors
          }
        }
      GQL
    end

    let(:variables) do
      {
        name: 'my-repo',
        s: {
          url: 'https://robot-user-9c1:robot-pass-3f7@upstream.test',
          credentials: { username: 'robot-user-9c1', password: 'robot-pass-3f7' }
        }
      }
    end

    it 'keeps the credential out of the GraphQL variable log', :aggregate_failures do
      post_graphql(query, current_user: current_user, variables: variables)

      logged = graphql_log.map { |payload| payload[:variables].to_s }

      expect(logged).not_to be_empty
      expect(logged).to all(exclude('robot-user-9c1', 'robot-pass-3f7'))
    end
  end
end
