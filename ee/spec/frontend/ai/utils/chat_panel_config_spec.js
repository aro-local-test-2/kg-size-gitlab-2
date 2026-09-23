import {
  parseChatPanelConfig,
  buildChatConfiguration,
  getChatPanelConfig,
  resetCachedChatPanelConfigForTesting,
} from 'ee/ai/utils/chat_panel_config';

describe('chat_panel_config', () => {
  afterEach(() => {
    resetCachedChatPanelConfigForTesting();
  });

  const createPanelElement = (dataset = {}) => {
    const el = document.createElement('div');
    Object.assign(el.dataset, {
      userId: 'gid://gitlab/User/1',
      projectId: 'gid://gitlab/Project/123',
      namespaceId: 'gid://gitlab/Group/456',
      rootNamespaceId: 'gid://gitlab/Group/789',
      resourceId: 'gid://gitlab/Resource/111',
      metadata: '{"key":"value"}',
      userModelSelectionEnabled: 'true',
      agenticAvailable: 'true',
      classicAvailable: 'false',
      chatTitle: 'GitLab Duo Chat',
      chatDisabledReason: '',
      autoExpand: 'true',
      ...dataset,
    });
    return el;
  };

  describe('parseChatPanelConfig', () => {
    it('parses every dataset key with its exact coercion and default', () => {
      const el = createPanelElement({
        projectPath: 'group/project',
        forceAgenticModeForCoreDuoUsers: 'false',
        agenticUnavailableMessage: 'Not available here',
        duoSettingsPath: '/admin/duo',
        defaultNamespaceSelected: 'true',
        preferencesPath: '/-/profile/preferences',
        isTrial: 'true',
        buyAddonPath: '/buy',
        canBuyAddon: 'true',
        purchaseCreditsPath: '/credits',
        tierUpgradePath: '/upgrade',
        trialActive: 'true',
        subscriptionActive: 'true',
        subscriptionExpired: 'false',
        exploreAiCatalogPath: '/ai/catalog',
        containerType: 'project',
        newTrialPath: '/trials/new',
        trialDuration: '60',
        isFreeAddonCreditsUser: 'false',
        duoAgentPlatformEnabled: 'true',
        isTrialExpired: 'false',
        isDuoDisabledNonAdmin: 'false',
        canStartTrial: 'false',
        accessDenied: 'false',
        identityVerificationRequired: 'false',
        identityVerificationPath: '/identity',
        isSaas: 'true',
        webSearchAllowedForGroup: 'true',
      });

      expect(parseChatPanelConfig(el, { isHandRaiseLeadAvailable: true })).toEqual({
        scope: {
          userId: 'gid://gitlab/User/1',
          projectId: 'gid://gitlab/Project/123',
          namespaceId: 'gid://gitlab/Group/456',
          rootNamespaceId: 'gid://gitlab/Group/789',
          resourceId: 'gid://gitlab/Resource/111',
          metadata: '{"key":"value"}',
          userModelSelectionEnabled: true,
          chatDisabledReason: '',
        },
        defaultProps: {
          userId: 'gid://gitlab/User/1',
          projectId: 'gid://gitlab/Project/123',
          projectPath: 'group/project',
          namespaceId: 'gid://gitlab/Group/456',
          rootNamespaceId: 'gid://gitlab/Group/789',
          resourceId: 'gid://gitlab/Resource/111',
          metadata: '{"key":"value"}',
          agenticUnavailableMessage: 'Not available here',
          userModelSelectionEnabled: true,
          chatDisabledReason: '',
          isDuoDisabled: false,
          isAgenticAvailable: true,
          isClassicAvailable: false,
          forceAgenticModeForCoreDuoUsers: false,
          chatTitle: 'GitLab Duo Chat',
          canConfigureDuoSettings: true,
          duoSettingsPath: '/admin/duo',
          defaultNamespaceSelected: true,
          defaultNamespaceRequired: false,
          preferencesPath: '/-/profile/preferences',
          isTrial: true,
          isTrialExpired: false,
          buyAddonPath: '/buy',
          canBuyAddon: true,
          purchaseCreditsPath: '/credits',
          tierUpgradePath: '/upgrade',
          isSaas: true,
          trialActive: true,
          subscriptionActive: true,
          isSubscriptionExpired: false,
          exploreAiCatalogPath: '/ai/catalog',
          isDuoDisabledNonAdmin: false,
          isFreeAddonCreditsUser: false,
          isHandRaiseLeadAvailable: true,
          containerType: 'project',
          isDuoDisabledForAdmin: '',
          canStartTrial: false,
          newTrialPath: '/trials/new',
          trialDuration: '60',
          accessDenied: false,
          identityVerificationRequired: false,
          identityVerificationPath: '/identity',
          shouldShowBlockedState: false,
          isDuoAgentPlatformEnabled: true,
        },
        shouldShowBlockedState: false,
        webSearchAllowedForGroup: true,
        autoExpand: true,
        forceAgenticModeForCoreDuoUsers: false,
        chatTitle: 'GitLab Duo Chat',
      });
    });

    it.each`
      webSearchAllowedForGroup | expected
      ${'true'}                | ${true}
      ${'false'}               | ${false}
      ${undefined}             | ${false}
    `(
      'parses webSearchAllowedForGroup as $expected when the data attribute is $webSearchAllowedForGroup',
      ({ webSearchAllowedForGroup, expected }) => {
        const config = parseChatPanelConfig(createPanelElement({ webSearchAllowedForGroup }));

        expect(config.webSearchAllowedForGroup).toBe(expected);
      },
    );

    it('returns the scope values used to mount a chat surface', () => {
      const { scope } = parseChatPanelConfig(createPanelElement());

      expect(scope).toEqual({
        userId: 'gid://gitlab/User/1',
        projectId: 'gid://gitlab/Project/123',
        namespaceId: 'gid://gitlab/Group/456',
        rootNamespaceId: 'gid://gitlab/Group/789',
        resourceId: 'gid://gitlab/Resource/111',
        metadata: '{"key":"value"}',
        userModelSelectionEnabled: true,
        chatDisabledReason: '',
      });
    });

    it('parses availability booleans into defaultProps', () => {
      const { defaultProps } = parseChatPanelConfig(createPanelElement());

      expect(defaultProps.isAgenticAvailable).toBe(true);
      expect(defaultProps.isClassicAvailable).toBe(false);
      expect(defaultProps.isDuoDisabled).toBe(false);
    });

    it('marks chat as disabled when a disabled reason is present', () => {
      const { defaultProps } = parseChatPanelConfig(
        createPanelElement({ chatDisabledReason: 'not_available' }),
      );

      expect(defaultProps.isDuoDisabled).toBe(true);
    });

    it('parses autoExpand and forceAgenticModeForCoreDuoUsers', () => {
      const config = parseChatPanelConfig(
        createPanelElement({ forceAgenticModeForCoreDuoUsers: 'true' }),
      );

      expect(config.autoExpand).toBe(true);
      expect(config.forceAgenticModeForCoreDuoUsers).toBe(true);
    });

    it('passes isHandRaiseLeadAvailable through to defaultProps', () => {
      const { defaultProps } = parseChatPanelConfig(createPanelElement(), {
        isHandRaiseLeadAvailable: true,
      });

      expect(defaultProps.isHandRaiseLeadAvailable).toBe(true);
    });

    it.each`
      attribute                         | value
      ${'isTrialExpired'}               | ${'true'}
      ${'isDuoDisabledNonAdmin'}        | ${'true'}
      ${'subscriptionExpired'}          | ${'true'}
      ${'canStartTrial'}                | ${'true'}
      ${'accessDenied'}                 | ${'true'}
      ${'identityVerificationRequired'} | ${'true'}
    `('computes shouldShowBlockedState from $attribute', ({ attribute, value }) => {
      const config = parseChatPanelConfig(createPanelElement({ [attribute]: value }));

      expect(config.shouldShowBlockedState).toBe(true);
      expect(config.defaultProps.shouldShowBlockedState).toBe(true);
    });

    it('requires a default namespace on SaaS when no namespace or project is set', () => {
      const config = parseChatPanelConfig(
        createPanelElement({
          isSaas: 'true',
          defaultNamespaceSelected: 'false',
          projectId: '',
          namespaceId: '',
        }),
      );

      expect(config.shouldShowBlockedState).toBe(true);
      expect(config.defaultProps.defaultNamespaceRequired).toBe(true);
    });

    it('does not require a default namespace when the chat is scoped to a project', () => {
      const config = parseChatPanelConfig(createPanelElement({ isSaas: 'true' }));

      expect(config.shouldShowBlockedState).toBe(false);
      expect(config.defaultProps.defaultNamespaceRequired).toBe(false);
    });

    it('treats a disabled reason with a settings path as a blocked state', () => {
      const config = parseChatPanelConfig(
        createPanelElement({
          chatDisabledReason: 'not_available',
          duoSettingsPath: '/admin/duo',
        }),
      );

      expect(config.shouldShowBlockedState).toBe(true);
    });

    it('does not treat a disabled reason without a settings path as a blocked state', () => {
      const config = parseChatPanelConfig(
        createPanelElement({ chatDisabledReason: 'not_available' }),
      );

      expect(config.shouldShowBlockedState).toBe(false);
      expect(config.defaultProps.isDuoDisabledForAdmin).toBe(false);
      expect(config.defaultProps.isDuoDisabled).toBe(true);
    });

    it('does not report a blocked state on a plain usable dataset', () => {
      const config = parseChatPanelConfig(createPanelElement());

      expect(config.shouldShowBlockedState).toBe(false);
    });
  });

  describe('getChatPanelConfig', () => {
    it('does not cache a miss and parses the live element once it exists', () => {
      expect(getChatPanelConfig()).toBe(null);

      const el = createPanelElement();
      el.id = 'duo-chat-panel';
      document.body.appendChild(el);
      const config = getChatPanelConfig();
      el.remove();

      expect(config.scope.userId).toBe('gid://gitlab/User/1');
      expect(getChatPanelConfig()).toBe(config);
    });

    it('returns the config cached by a previous parse after the element is gone', () => {
      const config = parseChatPanelConfig(createPanelElement());

      expect(getChatPanelConfig()).toBe(config);
    });
  });

  describe('buildChatConfiguration', () => {
    it('uses the dataset chat title for agentic chat and keeps defaultProps', () => {
      const config = parseChatPanelConfig(createPanelElement({ chatTitle: 'Custom Title' }));

      const chatConfiguration = buildChatConfiguration(config);

      expect(chatConfiguration.agenticTitle).toBe('Custom Title');
      expect(chatConfiguration.classicTitle).toBe('GitLab Duo Chat');
      expect(chatConfiguration.defaultProps).toBe(config.defaultProps);
    });

    it('falls back to the default agentic title', () => {
      const config = parseChatPanelConfig(createPanelElement({ chatTitle: '' }));

      expect(buildChatConfiguration(config).agenticTitle).toBe('GitLab Duo Agentic Chat');
    });
  });
});
