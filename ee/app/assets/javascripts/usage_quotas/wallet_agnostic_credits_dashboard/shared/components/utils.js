/**
 * Restricts date range options to the subscription period, mirroring the
 * clamping the backend applies in
 * ee/app/graphql/resolvers/gitlab_subscriptions/subscription_usage_resolver.rb.
 *
 * Options ending before the subscription started are dropped; options merely
 * starting before it are clamped. Both sides are `YYYY-MM-DD`, so string
 * comparison is chronological.
 *
 * @param {Array<Object>} options
 * @param {?string} subscriptionStartDate ISO date, or null when unknown
 * @returns {Array<Object>}
 */
export const availableDateRangeOptions = (options, subscriptionStartDate) => {
  if (!subscriptionStartDate) return options;

  return options
    .filter((option) => !option.endDate || option.endDate >= subscriptionStartDate)
    .map((option) =>
      option.startDate && option.startDate < subscriptionStartDate
        ? { ...option, startDate: subscriptionStartDate }
        : option,
    );
};

/**
 * Picks the initially selected range: the preferred option clamped to the
 * subscription period, or the option itself when the subscription has not
 * started yet (nothing to show, but the picker still needs a valid selection).
 *
 * @param {Object} option
 * @param {?string} subscriptionStartDate ISO date, or null when unknown
 * @returns {Object}
 */
export const initialDateRangeOption = (option, subscriptionStartDate) =>
  availableDateRangeOptions([option], subscriptionStartDate)[0] ?? option;
