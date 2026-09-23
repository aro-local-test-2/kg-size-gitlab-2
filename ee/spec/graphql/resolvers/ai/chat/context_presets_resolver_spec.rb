# frozen_string_literal: true

require "spec_helper"

RSpec.describe Resolvers::Ai::Chat::ContextPresetsResolver, feature_category: :duo_chat do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:current_user) { project.owner }
  let_it_be(:issue) { create(:issue, project: project) }

  describe "#resolve" do
    subject(:resolver) do
      resolve(
        described_class,
        obj: nil,
        args: args,
        ctx: { current_user: current_user },
        field_opts: { calls_gitaly: true }
      )
    end

    context "with set number of questions" do
      let(:question_count) { 2 }
      let(:args) { { question_count: question_count } }

      it "returns required amount of questions" do
        expect(resolver[:questions].size).to eq(question_count)
      end

      it "returns question categories unaffected by question_count" do
        expect(resolver[:question_categories].map { |category| category[:key] })
          .to eq(%w[get_started development work_items merge_requests pipelines security])
        expect(resolver[:question_categories].map { |category| category[:questions].size })
          .to all(be > question_count)
      end
    end

    context "with a foundational agent reference" do
      include_context 'with mocked Foundational Chat Agents'

      let(:mocked_foundational_chat_agents) do
        [foundational_duo_chat_agent, foundational_chat_agent_with_questions]
      end

      let(:agent_questions) { foundational_chat_agent_with_questions[:suggested_questions] }
      let(:selectable_agents) { ::Ai::FoundationalChatAgent.all }
      let(:args) { { foundational_agent_reference: 'agent_with_questions', question_count: 4 } }

      before do
        allow_next_instance_of(::Ai::FoundationalChatAgentsFinder) do |finder|
          allow(finder).to receive(:execute).and_return(selectable_agents)
        end
      end

      it "returns questions of that agent" do
        expect(resolver[:questions]).to have_attributes(size: 4).and all(be_in(agent_questions))
      end

      it "looks the agent up among the ones the user may select" do
        expect(::Ai::FoundationalChatAgentsFinder).to receive(:new)
          .with(current_user, project_id: nil, namespace_id: nil)
          .and_return(instance_double(::Ai::FoundationalChatAgentsFinder, execute: selectable_agents))

        resolver
      end

      context "when the user may not select that agent" do
        let(:selectable_agents) { ::Ai::FoundationalChatAgent.only_duo_chat_agent }

        it "falls back to the default questions" do
          expect(resolver[:questions]).to have_attributes(size: 4)
          expect(resolver[:questions]).not_to include(*agent_questions)
        end
      end

      context "when the reference matches no agent" do
        let(:args) { { foundational_agent_reference: 'does_not_exist', question_count: 4 } }

        it "falls back to the default questions" do
          expect(resolver[:questions]).to have_attributes(size: 4)
          expect(resolver[:questions]).not_to include(*agent_questions)
        end
      end
    end

    context "without a foundational agent reference" do
      let(:args) { { question_count: 4 } }

      it "does not look up an agent" do
        expect(::Ai::FoundationalChatAgentsFinder).not_to receive(:new)
        expect(::Gitlab::Duo::Chat::DefaultQuestions).to receive(:new)
          .with(anything, hash_including(foundational_agent: nil))
          .and_call_original

        resolver
      end
    end

    context "with specified resource" do
      let(:args) { { resource_id: resource_id, project_id: project_id } }
      let(:resource_id) { GitlabSchema.id_from_object(issue) }

      before do
        allow(Ability).to receive(:allowed?).and_return(true)
      end

      context "with specified project id" do
        let(:project_id) { GitlabSchema.id_from_object(project) }

        it "founds AI resource and passes it to the question service" do
          expect(::Gitlab::Duo::Chat::DefaultQuestions).to receive(:new)
            .with(anything, hash_including(resource: kind_of(Ai::AiResource::Issue)))
            .and_call_original

          expect(resolver[:ai_resource_data]).to match(/id.+#{issue.id}/)
        end
      end

      context "without specified resource id" do
        let(:resource_id) { nil }
        let(:project_id) { GitlabSchema.id_from_object(project) }

        it "does not pass an AI resource" do
          expect(::Gitlab::Duo::Chat::DefaultQuestions).to receive(:new)
            .with(anything, hash_including(resource: nil))
            .and_call_original

          expect(resolver[:ai_resource_data]).to be_nil
        end
      end

      context 'when user is missing' do
        let(:project_id) { GitlabSchema.id_from_object(project) }
        let(:current_user) { nil }

        it "does not pass an AI resource" do
          expect(resolver[:ai_resource_data]).to be_nil
        end
      end

      context "with commit resource" do
        let(:project_id) { GitlabSchema.id_from_object(project) }
        let(:commit) { project.repository.commit }
        let(:resource_id) { GitlabSchema.id_from_object(commit) }

        it "founds AI resource and passes it to the question service" do
          expect(::Gitlab::Duo::Chat::DefaultQuestions).to receive(:new)
            .with(anything, hash_including(resource: kind_of(Ai::AiResource::Commit)))
            .and_call_original

          expect(resolver[:ai_resource_data]).to match(/id.+#{commit.id}/)
        end
      end

      context "with not AI resource" do
        let(:not_supported_resource) { create(:vulnerability, project: project) }
        let(:resource_id) { GitlabSchema.id_from_object(not_supported_resource) }
        let(:project_id) { GitlabSchema.id_from_object(project) }

        it "does not pass the resource" do
          expect(::Gitlab::Duo::Chat::DefaultQuestions).to receive(:new)
            .with(anything, hash_including(resource: nil))
            .and_call_original

          expect(resolver[:ai_resource_data]).to be_nil
        end
      end
    end
  end
end
