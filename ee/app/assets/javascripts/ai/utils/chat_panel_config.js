import { parseBoolean } from '~/lib/utils/common_utils';
import { __ } from '~/locale';

/**
 * Parses the `#duo-chat-panel` dataset rendered by the
 * DuoChatPanel::*Component HAML templates into the config objects the Duo
 * chat surfaces need. Single source of truth for the global AI panel
 * (init_duo_panel.js) and page-embedded chat surfaces, so consumers cannot
 * drift.
 *
 * @param {HTMLElement} el - the `#duo-chat-panel` element
 * @param {Object} options
 * @param {boolean} options.isHandRaiseLeadAvailable
 * @returns {{
 *   scope: Object,
 *   defaultProps: Object,
 *   shouldShowBlockedState: boolean,
 *   autoExpand: boolean,
 *   forceAgenticModeForCoreDuoUsers: boolean,
 *   chatTitle: string|undefined,
 * }}
 */
// The AI panel's Vue app mounts into #duo-chat-panel and a Vue mount
// REPLACES the element, so the id (and its dataset) disappear from the live
// DOM once the panel initializes. The parsed config is cached here so other
// consumers (for example the Duo home embedded chat) can read it without
// racing the panel mount.
let cachedConfig = null;

export const resetCachedChatPanelConfigForTesting = () => {
  cachedConfig = null;
};

/**
 * Returns the config parsed by the panel's own initialization, or parses the
 * live `#duo-chat-panel` element on first call. Returns null when the panel
 * was never rendered on the page (CE, Duo unavailable): callers must handle
 * null before passing the result to buildChatConfiguration.
 */
export const getChatPanelConfig = () => {
  if (cachedConfig) return cachedConfig;

  const el = document.getElementById('duo-chat-panel');
  // eslint-disable-next-line no-use-before-define
  if (el) cachedConfig = parseChatPanelConfig(el);
  return cachedConfig;
};

export const parseChatPanelConfig = (el, { isHandRaiseLeadAvailable = false } = {}) => {
  const {
    userId,
    projectId,
    projectPath,
    namespaceId,
    rootNamespaceId,
    resourceId,
    metadata,
    userModelSelectionEnabled,
    agenticAvailable,
    classicAvailable,
    forceAgenticModeForCoreDuoUsers,
    agenticUnavailableMessage,
    chatTitle,
    chatDisabledReason,
    duoSettingsPath,
    defaultNamespaceSelected,
    preferencesPath,
    isTrial,
    buyAddonPath,
    canBuyAddon,
    purchaseCreditsPath,
    tierUpgradePath,
    trialActive,
    subscriptionActive,
    subscriptionExpired,
    exploreAiCatalogPath,
    autoExpand,
    containerType,
    newTrialPath,
    trialDuration,
    isFreeAddonCreditsUser,
    duoAgentPlatformEnabled,
    webSearchAllowedForGroup,
  } = el.dataset;

  const canConfigureDuoSettings = Boolean(duoSettingsPath);
  const isTrialExpired = parseBoolean(el.dataset.isTrialExpired);
  const isDuoDisabledForAdmin = chatDisabledReason && canConfigureDuoSettings;
  const isDuoDisabledNonAdmin = parseBoolean(el.dataset.isDuoDisabledNonAdmin);
  const isSubscriptionExpired = parseBoolean(subscriptionExpired);
  const canStartTrial = parseBoolean(el.dataset.canStartTrial);
  const accessDenied = parseBoolean(el.dataset.accessDenied);
  const identityVerificationRequired = parseBoolean(el.dataset.identityVerificationRequired);
  const { identityVerificationPath } = el.dataset;
  const isSaas = parseBoolean(el.dataset.isSaas);
  const isDefaultNamespaceSelected = parseBoolean(defaultNamespaceSelected);
  const defaultNamespaceRequired =
    isSaas && !isDefaultNamespaceSelected && !namespaceId && !projectId;
  const shouldShowBlockedState =
    isDuoDisabledForAdmin ||
    isDuoDisabledNonAdmin ||
    isTrialExpired ||
    isSubscriptionExpired ||
    canStartTrial ||
    accessDenied ||
    identityVerificationRequired ||
    defaultNamespaceRequired;

  const config = {
    scope: {
      userId,
      projectId,
      namespaceId,
      rootNamespaceId,
      resourceId,
      metadata,
      userModelSelectionEnabled: parseBoolean(userModelSelectionEnabled),
      chatDisabledReason,
    },
    defaultProps: {
      userId,
      projectId,
      projectPath,
      namespaceId,
      rootNamespaceId,
      resourceId,
      metadata,
      agenticUnavailableMessage,
      userModelSelectionEnabled: parseBoolean(userModelSelectionEnabled),
      chatDisabledReason,
      isDuoDisabled: Boolean(chatDisabledReason),
      isAgenticAvailable: parseBoolean(agenticAvailable),
      isClassicAvailable: parseBoolean(classicAvailable),
      forceAgenticModeForCoreDuoUsers: parseBoolean(forceAgenticModeForCoreDuoUsers),
      chatTitle,
      canConfigureDuoSettings,
      duoSettingsPath,
      defaultNamespaceSelected: isDefaultNamespaceSelected,
      defaultNamespaceRequired,
      preferencesPath,
      isTrial: parseBoolean(isTrial),
      isTrialExpired,
      buyAddonPath,
      canBuyAddon: parseBoolean(canBuyAddon),
      purchaseCreditsPath,
      tierUpgradePath,
      isSaas,
      trialActive: parseBoolean(trialActive ?? 'false'),
      subscriptionActive: parseBoolean(subscriptionActive ?? 'false'),
      isSubscriptionExpired,
      exploreAiCatalogPath,
      isDuoDisabledNonAdmin,
      isFreeAddonCreditsUser: parseBoolean(isFreeAddonCreditsUser),
      isHandRaiseLeadAvailable,
      containerType,
      isDuoDisabledForAdmin,
      canStartTrial,
      newTrialPath,
      trialDuration,
      accessDenied,
      identityVerificationRequired,
      identityVerificationPath,
      shouldShowBlockedState,
      isDuoAgentPlatformEnabled: parseBoolean(duoAgentPlatformEnabled),
    },
    shouldShowBlockedState,
    webSearchAllowedForGroup: parseBoolean(webSearchAllowedForGroup),
    autoExpand: parseBoolean(autoExpand),
    forceAgenticModeForCoreDuoUsers: parseBoolean(forceAgenticModeForCoreDuoUsers),
    chatTitle,
  };

  cachedConfig = config;
  return config;
};

/**
 * Builds the `chatConfiguration` object injected into the chat state
 * managers. Callers that also drive the AI panel router spread their own
 * component references and `autoExpand` on top.
 */
export const buildChatConfiguration = ({ chatTitle, defaultProps }) => ({
  agenticTitle: chatTitle || __('GitLab Duo Agentic Chat'),
  classicTitle: __('GitLab Duo Chat'),
  defaultProps,
});
