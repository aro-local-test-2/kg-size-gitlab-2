# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gitlab::Duo::Chat::DefaultQuestions, feature_category: :duo_chat do
  describe "#execute" do
    subject do
      described_class.new(
        user,
        url: url,
        resource: resource,
        foundational_agent: foundational_agent
      ).execute
    end

    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project) }
    let_it_be(:group) { create(:group) }
    let(:url) { nil }
    let(:foundational_agent) { nil }

    context "with allowed resource" do
      context "with issue resource" do
        let(:issue) { build_stubbed(:issue, project: project) }
        let(:resource) { ::Ai::AiResource::Issue.new(user, issue) }

        before do
          allow(user).to receive(:allowed_to_use?)
            .with(:ask_issue, root_namespace: project.root_ancestor)
            .and_return(true)
        end

        it { is_expected.to include("What key decisions were made in this issue?") }
      end

      context "with merge request resource" do
        let(:merge_request) { build_stubbed(:merge_request, source_project: project) }
        let(:resource) { ::Ai::AiResource::MergeRequest.new(user, merge_request) }

        before do
          allow(user).to receive(:allowed_to_use?)
            .with(:ask_merge_request, root_namespace: project.root_ancestor)
            .and_return(true)
        end

        it { is_expected.to include("What changed in this diff?") }
      end

      context "with ci job resource" do
        let(:ci_build) { build_stubbed(:ci_build, project: project) }
        let(:resource) { ::Ai::AiResource::Ci::Build.new(user, ci_build) }

        before do
          allow(user).to receive(:allowed_to_use?)
            .with(:ask_build, root_namespace: project.root_ancestor)
            .and_return(true)
        end

        it { is_expected.to include("What was each stage's final status?") }
      end

      context "with epic resource" do
        let(:group) { create(:group) }
        let(:epic) { build_stubbed(:epic, group: group) }
        let(:resource) { ::Ai::AiResource::Epic.new(user, epic) }

        before do
          allow(user).to receive(:allowed_to_use?)
            .with(:ask_epic, root_namespace: group.root_ancestor)
            .and_return(true)
        end

        it { is_expected.to include("What key features are planned?") }
      end

      context "with commit resource" do
        let(:commit) { build_stubbed(:commit, project: project) }
        let(:resource) { ::Ai::AiResource::Commit.new(user, commit) }

        before do
          allow(user).to receive(:allowed_to_use?)
            .with(:ask_commit, root_namespace: project.root_ancestor)
            .and_return(true)
        end

        it { is_expected.to include("How can I test these changes?") }
      end
    end

    context "without allowed resource" do
      let(:issue) { build_stubbed(:issue, project: project) }
      let(:resource) { ::Ai::AiResource::Issue.new(user, issue) }

      before do
        allow(user).to receive(:allowed_to_use?)
          .with(:ask_issue, root_namespace: project.root_ancestor)
          .and_return(false)
      end

      it "returns default questions" do
        is_expected.to include("How do I estimate story points?")
      end
    end

    context "with code url" do
      let(:url) { Gitlab::Routing.url_helpers.project_blob_url(project, 'readme.md') }
      let(:resource) { nil }

      it { is_expected.to include("What does this code do?") }
    end

    context "with project wiki url" do
      let(:url) { Gitlab::Routing.url_helpers.project_wiki_url(project, 'home') }
      let(:resource) { nil }

      it "returns the wiki related questions" do
        is_expected.to include("Where can I see page version history?")
      end
    end

    context "with group wiki url" do
      let(:url) { Gitlab::Routing.url_helpers.group_wiki_url(group, 'home') }
      let(:resource) { nil }

      it "returns the wiki related questions" do
        is_expected.to include("Where can I see page version history?")
      end
    end

    context "with a foundational agent" do
      include_context 'with mocked Foundational Chat Agents'

      let(:mocked_foundational_chat_agents) do
        [foundational_duo_chat_agent, foundational_chat_agent_with_questions]
      end

      let(:agent_questions) { foundational_chat_agent_with_questions[:suggested_questions] }
      let(:resource) { nil }

      context "when the agent defines suggested questions" do
        let(:foundational_agent) { ::Ai::FoundationalChatAgent.find_by_reference('agent_with_questions') }

        it "returns the questions of the agent" do
          is_expected.to eq(agent_questions)
        end

        context "with a resource the user may ask about" do
          let(:issue) { build_stubbed(:issue, project: project) }
          let(:resource) { ::Ai::AiResource::Issue.new(user, issue) }

          before do
            allow(user).to receive(:allowed_to_use?)
              .with(:ask_issue, root_namespace: project.root_ancestor)
              .and_return(true)
          end

          it "takes precedence over the resource questions" do
            is_expected.to eq(agent_questions)
          end
        end

        context "with a code url" do
          let(:url) { Gitlab::Routing.url_helpers.project_blob_url(project, 'readme.md') }

          it "takes precedence over the URL questions" do
            is_expected.to eq(agent_questions)
          end
        end
      end

      context "when the agent defines no suggested questions" do
        let(:foundational_agent) { ::Ai::FoundationalChatAgent.find_by_reference('chat') }

        it "returns default questions" do
          is_expected.to include("How do I estimate story points?")
        end
      end

      context "when no agent is given" do
        let(:foundational_agent) { nil }

        it "returns default questions" do
          is_expected.to include("How do I estimate story points?")
        end
      end
    end

    context "with random url" do
      let(:url) { Gitlab::Routing.url_helpers.project_url(project) }
      let(:resource) { nil }

      it "returns default questions" do
        is_expected.to include("How do I estimate story points?")
      end
    end
  end

  describe "#categories" do
    subject(:categories) { described_class.new(user, url: url, resource: resource).categories }

    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project) }
    let_it_be(:group) { create(:group) }
    let(:url) { nil }
    let(:resource) { nil }

    shared_examples "static categories" do
      it "returns the static categories in display order with titles" do
        static = categories.reject { |category| category[:contextual] }

        expect(static.map { |category| category[:key] })
          .to eq(%w[get_started development work_items merge_requests pipelines security])
        expect(static.map { |category| category[:contextual] }).to all(be(false))
        expect(static.map { |category| category[:title] }).to all(be_present)
        expect(static.map { |category| category[:questions] }).to all(be_present)
      end
    end

    shared_examples "no contextual category" do
      it "does not include a contextual category" do
        expect(categories.map { |category| category[:contextual] }).to all(be(false))
      end
    end

    context "without any context" do
      it_behaves_like "static categories"
      it_behaves_like "no contextual category"
    end

    context "with allowed merge request resource" do
      let(:merge_request) { build_stubbed(:merge_request, source_project: project) }
      let(:resource) { ::Ai::AiResource::MergeRequest.new(user, merge_request) }

      before do
        allow(user).to receive(:allowed_to_use?)
          .with(:ask_merge_request, root_namespace: project.root_ancestor)
          .and_return(true)
      end

      it_behaves_like "static categories"

      it "returns the contextual category first, keyed by page type and titled with the reference" do
        expect(categories.first).to match(
          key: 'merge_request',
          title: merge_request.to_reference,
          contextual: true,
          questions: include("What changed in this diff?")
        )
      end

      it "checks the entitlement once when a resolver asks for both questions and categories" do
        instance = described_class.new(user, url: url, resource: resource)

        instance.execute
        instance.categories

        expect(user).to have_received(:allowed_to_use?).once
      end
    end

    context "with a resource that has no reference" do
      let(:build) { build_stubbed(:ci_build, project: project) }
      let(:resource) { ::Ai::AiResource::Ci::Build.new(user, build) }

      before do
        allow(user).to receive(:allowed_to_use?)
          .with(:ask_build, root_namespace: project.root_ancestor)
          .and_return(true)
      end

      it "titles the contextual category after the page" do
        expect(categories.first).to match(
          key: 'build',
          title: 'This job',
          contextual: true,
          questions: include("What errors or warnings appeared in this job?")
        )
      end
    end

    context "with a resource that has no chat questions" do
      let(:pipeline) { build_stubbed(:ci_pipeline, project: project) }
      let(:resource) { ::Ai::AiResource::Ci::Pipeline.new(user, pipeline) }

      before do
        allow(user).to receive(:allowed_to_use?)
          .with(:duo_chat, root_namespace: project.root_ancestor)
          .and_return(true)
      end

      it_behaves_like "static categories"
      it_behaves_like "no contextual category"
    end

    context "without allowed resource" do
      let(:issue) { build_stubbed(:issue, project: project) }
      let(:resource) { ::Ai::AiResource::Issue.new(user, issue) }

      before do
        allow(user).to receive(:allowed_to_use?)
          .with(:ask_issue, root_namespace: project.root_ancestor)
          .and_return(false)
      end

      it_behaves_like "static categories"
      it_behaves_like "no contextual category"
    end

    context "with project wiki url" do
      let(:url) { Gitlab::Routing.url_helpers.project_wiki_url(project, 'home') }

      it_behaves_like "static categories"

      it "returns the contextual category keyed as a wiki" do
        expect(categories.first).to match(
          key: 'wiki',
          title: 'This page',
          contextual: true,
          questions: include("Where can I see page version history?")
        )
      end
    end

    context "with code url" do
      let(:url) { Gitlab::Routing.url_helpers.project_blob_url(project, 'readme.md') }

      it_behaves_like "static categories"

      it "returns the contextual category keyed as a blob with the page-specific code questions" do
        expect(categories.first).to match(
          key: 'blob',
          title: 'This file',
          contextual: true,
          questions: include("What does this code do?")
        )
      end

      it "keeps the page-specific code questions out of the static code category" do
        static_development = categories.find { |category| category[:key] == 'development' }

        expect(static_development[:questions]).not_to include("What does this code do?")
        expect(static_development[:questions]).to include("Show me automated testing strategies")
      end
    end

    context "with a url that has no page-specific questions" do
      let(:url) { Gitlab::Routing.url_helpers.project_url(project) }

      it_behaves_like "static categories"
      it_behaves_like "no contextual category"
    end

    context "with both a resource and a page-specific url" do
      let(:url) { Gitlab::Routing.url_helpers.project_blob_url(project, 'readme.md') }
      let(:merge_request) { build_stubbed(:merge_request, source_project: project) }
      let(:resource) { ::Ai::AiResource::MergeRequest.new(user, merge_request) }

      before do
        allow(user).to receive(:allowed_to_use?)
          .with(:ask_merge_request, root_namespace: project.root_ancestor)
          .and_return(true)
      end

      it "prefers the resource over the page type" do
        expect(categories.first).to match(
          key: 'merge_request',
          title: merge_request.to_reference,
          contextual: true,
          questions: include("What changed in this diff?")
        )
      end
    end
  end
end
