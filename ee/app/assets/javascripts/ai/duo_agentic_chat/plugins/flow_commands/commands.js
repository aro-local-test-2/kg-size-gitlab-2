import { slugify } from '~/lib/utils/text_utility';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { FLOW_COMMAND_PREFIX } from './constants';

const commandName = (slug) => `${FLOW_COMMAND_PREFIX}${slug}`;

const uniqueCommandName = (slug, consumerId, seen) => {
  let name = slug;
  // The consumer id is unique, but another flow's name can slugify onto the suffixed
  // form, so keep appending until the command name is free.
  while (seen.has(commandName(name))) name = `${name}-${consumerId}`;

  return commandName(name);
};

/**
 * Builds one slash command per AI Catalog flow enabled in the project.
 *
 * Two flows can slugify to the same name, so collisions are disambiguated by appending
 * the consumer ID. That is deliberately ugly: it surfaces the problem rather than
 * silently dropping a flow, and a real fix (author-supplied command names on the catalog
 * item) needs a schema change.
 *
 * `consumerId` rides along as plain data. The prompt builder hands the whole command
 * object back on `userPrompt.slashCommands`, so the send path reads the id from there
 * rather than the plugin having to be called back.
 *
 * @param {Array} consumers - `aiCatalogConfiguredItems.nodes`
 * @returns {import('../../services/plugin_capabilities/slash_commands').SlashCommand[]}
 */
export const buildFlowCommands = (consumers = []) => {
  const seen = new Set();

  return consumers.reduce((commands, consumer) => {
    const flow = consumer?.item;
    if (!flow?.name) return commands;

    const consumerId = getIdFromGraphQLId(consumer.id);
    const slug = slugify(flow.name) || `flow-${consumerId}`;
    const value = uniqueCommandName(slug, consumerId, seen);

    seen.add(value);

    commands.push({
      value,
      label: flow.name,
      description: flow.description || flow.name,
      startOnly: true,
      consumerId,
    });

    return commands;
  }, []);
};
