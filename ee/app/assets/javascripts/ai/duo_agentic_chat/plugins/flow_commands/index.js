import { s__ } from '~/locale';
import getConfiguredFlowsForChat from 'ee/ai/graphql/get_configured_flows_for_chat.query.graphql';
import { buildFlowCommands } from './commands';
/**
 * Starting an AI Catalog flow from the composer.
 *
 * A flow can otherwise only run if a trigger is attached to it, which leaves flows like a
 * repository-wide scan with no sensible way to be started at all.
 *
 * What the command adds to the turn it starts lives in
 * `context/slash_commands_context.js`, since sending it is the core's job.
 *
 * @type {import('../../services/plugin_registry').DuoChatPlugin}
 */
export const flowCommandsPlugin = {
  name: 'flow_commands',
  slashCommands: [
    {
      async getCommands({ apollo, duoChatContext }) {
        // Flows are enabled per project. No project, no flows.
        if (!duoChatContext?.projectId) return [];

        const { data } = await apollo.query({
          query: getConfiguredFlowsForChat,
          variables: { projectId: duoChatContext.projectId },
          context: { featureCategory: 'duo_agent_platform' },
        });

        const commands = buildFlowCommands(data?.aiCatalogConfiguredItems?.nodes);

        // One section, so the menu reads as a list of flow names rather than tokens.
        return commands.length ? [{ label: s__('AICatalog|Flows'), items: commands }] : [];
      },
    },
  ],
};
