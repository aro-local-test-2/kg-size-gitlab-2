import { waitFor } from '@testing-library/vue';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getText } from 'ee_jest/integration/helpers/test_helpers';
import {
  getAiChatAvailableModelsUnpinned,
  aiChatAvailableModelsVariants,
  installDuoAIPanelHandlers,
} from '../test_support/api_handlers';
import {
  buildChatConfiguration,
  findChatToggle,
  findModelItem,
  findModelToggle,
  findModelToggleText,
  findSubmitButton,
  mountAISidebar,
  openChatTab,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import { getSockets, lastWebsocketParams, waitForSocket } from '../test_support/websocket_mock';

// Replaces the "allows user to select a model" example from
// ee/spec/support/shared_examples/ai/agentic_chat_shared_example.rb.
//
// The Capybara original only asserted that *a* reply came back after switching
// models, which does not prove the choice reached the wire. Here the selection is
// asserted on the websocket URL the client opens, and the pinned-model case (which
// the original never covered) is asserted too.
//
// Both selector implementations are covered. Behind `newModelSelection` the model
// no longer comes from the state manager's own query: `ChatModelSelector` owns it
// and reports it upwards, which is exactly the wiring a unit test with a stubbed
// child cannot prove reaches the websocket URL.

const availableModels = getAiChatAvailableModelsUnpinned.models();
const DEFAULT_MODEL = availableModels.defaultModel;
const OTHER_MODEL = availableModels.selectableModels.find(
  (model) => model.ref !== DEFAULT_MODEL.ref,
);

// Without this the selection test fails deep inside a `waitFor` on a missing
// `.ref`, which says nothing about the fixture being the cause.
if (!OTHER_MODEL) {
  throw new Error(
    'The unpinned models fixture needs a second selectable model to switch to. ' +
      'Regenerate with: bundle exec rspec ee/spec/frontend/fixtures/ai_duo_panel_integration.rb',
  );
}
// The gateway bakes the hosting provider into the name ("Claude Sonnet 4.5 -
// Bedrock"). The redesigned toggle strips it, and drops the legacy " - Default"
// suffix because Default is a badge on the list row now.
const compactName = ({ name, modelProvider }) => {
  const suffix = ` - ${modelProvider}`;

  return modelProvider && name.endsWith(suffix) ? name.slice(0, -suffix.length) : name;
};

describe.each`
  selector                | newModelSelection | expectedToggleText
  ${'legacy dropdown'}    | ${false}          | ${`${DEFAULT_MODEL.name} - Default`}
  ${'new model selector'} | ${true}           | ${compactName(DEFAULT_MODEL)}
`(
  'Duo Agentic Chat | choosing a model ($selector)',
  ({ newModelSelection, expectedToggleText }) => {
    const mountPanel = ({ modelsPinned = false } = {}) => {
      installDuoAIPanelHandlers();

      // BASE is the pinned dropdown, so only the unpinned case needs a variant.
      if (!modelsPinned) {
        setQueryVariant(aiChatAvailableModelsVariants).unpinned();
      }

      mountAISidebar({
        chatConfiguration: buildChatConfiguration({
          defaultProps: { userModelSelectionEnabled: true },
        }),
        provide: { glFeatures: { newModelSelection } },
      });
    };

    const openChatAndWaitForModelDropdown = async () => {
      await waitFor(() => {
        expect(findChatToggle()).not.toBe(null);
      });

      openChatTab();

      await waitFor(() => {
        expect(findModelToggle()).not.toBe(null);
      });
    };

    beforeEach(setupDuoChatTest);

    afterEach(() => teardownDuoChatTest());

    it('shows the instance default model as the current choice', async () => {
      mountPanel();
      await openChatAndWaitForModelDropdown();

      await waitFor(() => {
        expect(getText(findModelToggleText())).toContain(expectedToggleText);
      });
    });

    it('sends the selected model identifier when opening the stream', async () => {
      mountPanel();
      await openChatAndWaitForModelDropdown();

      await waitFor(() => {
        expect(getText(findModelToggleText())).toContain(compactName(DEFAULT_MODEL));
      });

      findModelToggle().click();

      const item = await waitFor(() => {
        const option = findModelItem(OTHER_MODEL.ref);
        expect(option).not.toBe(null);
        return option;
      });

      item.click();

      // Choosing a model starts a fresh thread, so wait for the composer to come
      // back before prompting.
      await waitFor(() => {
        expect(findSubmitButton()).not.toBe(null);
      });

      const socketsBefore = getSockets().length;
      sendPrompt('which model are you?');

      await waitFor(() => {
        expect(getSockets()).toHaveLength(socketsBefore + 1);
      });
      await waitForSocket();

      expect(lastWebsocketParams().get('user_selected_model_identifier')).toBe(OTHER_MODEL.ref);
    });

    it('disables the dropdown when an administrator has pinned a model', async () => {
      mountPanel({ modelsPinned: true });
      await openChatAndWaitForModelDropdown();

      await waitFor(() => {
        expect(findModelToggle().getAttribute('aria-disabled')).toBe('true');
      });
    });
  },
);
