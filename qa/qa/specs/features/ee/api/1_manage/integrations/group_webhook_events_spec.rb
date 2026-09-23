# frozen_string_literal: true

module QA
  RSpec.describe 'Manage', feature_category: :importers do
    describe(
      'Group WebHooks integration',
      :requires_admin,
      :integrations,
      :orchestrated,
      feature_category: :importers
    ) do
      before(:context) do
        toggle_local_requests(true)
      end

      after(:context) do
        EE::Resource::GroupWebHook.teardown!
      end

      let(:session) { SecureRandom.hex(5) }

      it 'sends subgroup events' do
        EE::Resource::GroupWebHook.setup(session: session, subgroup: true) do |webhook, smocker|
          group = create(:group, sandbox: webhook.group)
          group.immediate_remove_via_api!

          expect { smocker.events(session).size }.to eventually_eq(2)
                                               .within(max_duration: 30, sleep_interval: 2),
            -> { "Should have 2 events, got: #{smocker.stringified_history(session)}" }

          events = smocker.events(session)

          expect(events).to include(
            a_hash_including(event_name: 'subgroup_create'),
            a_hash_including(event_name: 'subgroup_destroy')
          ),
            "Expected Create/Destroy Subgroup events, got: #{smocker.stringified_history(session)}"
        end
      end

      it 'sends a member event with expires_at as a midnight UTC timestamp' do
        EE::Resource::GroupWebHook.setup(session: session, member: true) do |webhook, smocker|
          user = create(:user)
          webhook.group.add_member(user, expires_at: '2030-12-14')

          expect { smocker.events(session).size }.to eventually_eq(1)
                                                 .within(max_duration: 30, sleep_interval: 2),
            -> { "Should have 1 event, got: #{smocker.stringified_history(session)}" }

          # members.expires_at is a date column, but ActiveSupport redefines
          # Date#xmlschema as in_time_zone.xmlschema, so the payload builder
          # renders it as a midnight UTC timestamp, not a bare date.
          expect(smocker.events(session).first).to match(a_hash_including(
            event_name: 'user_add_to_group',
            expires_at: '2030-12-14T00:00:00Z'
          ))
        end
      end

      context 'when hook fails', feature_flag: { name: :auto_disabling_web_hooks } do
        let(:fail_mock) do
          <<~YAML
            - request:
                method: POST
                path: /default
              response:
                status: 500
                headers:
                  Content-Type: text/plain
                body: 'webhook failed'
          YAML
        end

        let(:hook_trigger_times) { 5 }

        before do
          Runtime::Feature.enable(:auto_disabling_web_hooks)
        end

        it 'group hook is temporarily disabled after repeated failures' do
          EE::Resource::GroupWebHook.setup(fail_mock, session: session, issues: true) do |webhook, smocker|
            project = create(:project, group: webhook.group)

            hook_trigger_times.times do
              create(:issue, project: project)
              sleep 1
            end

            expect { smocker.events(session).size >= 4 }.to eventually_be_truthy
              .within(max_duration: 30, sleep_interval: 2),
              -> { "Should have at least 4 events, got: #{smocker.events(session).size}" }

            webhook.reload!

            expect { webhook.reload!.alert_status }.to eventually_eq('temporarily_disabled')
              .within(max_duration: 30, sleep_interval: 2),
              -> { "Expected temporarily_disabled, got: #{webhook.alert_status}" }
          end
        end
      end
    end

    private

    def toggle_local_requests(on)
      Runtime::ApplicationSettings.set_application_settings(allow_local_requests_from_web_hooks_and_services: on)
    end
  end
end
