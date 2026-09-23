import { flowCommandsPlugin } from 'ee/ai/duo_agentic_chat/plugins/flow_commands';
import getConfiguredFlowsForChat from 'ee/ai/graphql/get_configured_flows_for_chat.query.graphql';

describe('flow commands plugin', () => {
  const PROJECT_ID = 'gid://gitlab/Project/1';

  const consumer = (id, name, description = 'A description') => ({
    id: `gid://gitlab/Ai::Catalog::ItemConsumer/${id}`,
    item: { id: `gid://gitlab/Ai::Catalog::Item/${id}`, name, description },
  });

  const apolloReturning = (...consumers) => ({
    query: jest.fn().mockResolvedValue({
      data: { aiCatalogConfiguredItems: { nodes: consumers } },
    }),
  });

  const [{ getCommands }] = flowCommandsPlugin.slashCommands;

  const entriesFor = (apollo, duoChatContext = { projectId: PROJECT_ID }) =>
    getCommands({ apollo, duoChatContext });

  const commandsFor = async (apollo) => {
    const [group] = await entriesFor(apollo);

    return group?.items ?? [];
  };

  it('is filed under a name that identifies it in plugin reports', () => {
    expect(flowCommandsPlugin.name).toBe('flow_commands');
  });

  it('asks for the flows enabled in the project the chat is pointed at', async () => {
    const apollo = apolloReturning();

    await entriesFor(apollo);

    expect(apollo.query).toHaveBeenCalledWith(
      expect.objectContaining({
        query: getConfiguredFlowsForChat,
        variables: { projectId: PROJECT_ID },
      }),
    );
  });

  // Flows are enabled per project, so a group-level chat has nothing to offer and no
  // reason to ask.
  it.each([{}, { projectId: null }, undefined])(
    'offers nothing, and asks nothing, for a context of %p',
    async (duoChatContext) => {
      const apollo = apolloReturning();

      // Called directly rather than through the helper, whose default would stand in
      // for the very absence being tested.
      await expect(getCommands({ apollo, duoChatContext })).resolves.toEqual([]);
      expect(apollo.query).not.toHaveBeenCalled();
    },
  );

  describe('the commands it builds', () => {
    it('files every flow under one section', async () => {
      const entries = await entriesFor(apolloReturning(consumer(7, 'Security Scan')));

      expect(entries).toEqual([{ label: 'Flows', items: [expect.any(Object)] }]);
    });

    it('offers no section at all when the project has no flows', async () => {
      await expect(entriesFor(apolloReturning())).resolves.toEqual([]);
    });

    it('writes a namespaced command per flow, labelled with its name', async () => {
      const [command] = await commandsFor(apolloReturning(consumer(7, 'Security Scan', 'Scans')));

      expect(command).toMatchObject({
        value: '/flow:security-scan',
        label: 'Security Scan',
        description: 'Scans',
        startOnly: true,
        consumerId: 7,
      });
    });

    it('falls back to the flow name when it has no description', async () => {
      const [command] = await commandsFor(apolloReturning(consumer(7, 'Security Scan', null)));

      expect(command.description).toBe('Security Scan');
    });

    it('skips a consumer with no underlying flow', async () => {
      const apollo = apolloReturning({ id: 'gid://gitlab/Ai::Catalog::ItemConsumer/1' });

      await expect(commandsFor(apollo)).resolves.toEqual([]);
    });

    it('names a flow that slugifies to nothing after its consumer', async () => {
      const [command] = await commandsFor(apolloReturning(consumer(7, '!!!')));

      expect(command.value).toBe('/flow:flow-7');
    });

    // Deliberately ugly, so the collision is visible rather than a flow going missing.
    it('disambiguates two flows that slugify the same', async () => {
      const commands = await commandsFor(
        apolloReturning(consumer(1, 'Security Scan'), consumer(2, 'security scan')),
      );

      expect(commands.map((command) => command.value)).toEqual([
        '/flow:security-scan',
        '/flow:security-scan-2',
      ]);
    });

    // A third flow can be named such that the suffixed form is taken as well. Every
    // flow still has to come back with a name of its own, or the capability drops one.
    it('keeps going when the suffixed name collides too', async () => {
      const commands = await commandsFor(
        apolloReturning(
          consumer(9, 'Security Scan 2'),
          consumer(1, 'Security Scan'),
          consumer(2, 'security scan'),
        ),
      );

      expect(commands.map((command) => command.value)).toEqual([
        '/flow:security-scan-2',
        '/flow:security-scan',
        '/flow:security-scan-2-2',
      ]);
    });
  });
});
