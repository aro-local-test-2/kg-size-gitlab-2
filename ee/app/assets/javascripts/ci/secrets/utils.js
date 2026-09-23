import { s__ } from '~/locale';
import {
  ENTITLEMENT_STATE_BLOCKED,
  ENTITLEMENT_STATE_INELIGIBLE,
  ENTITLEMENT_STATE_TRIAL_ELIGIBLE,
} from './constants';

// Mirrors the backend write-entitlement rule (Entitlement#permits_writes?):
// any blocked reason and ineligibility deny provisioning, while active
// trial and paid states permit it.
export const isProvisioningBlockedByEntitlement = (entitlement) =>
  entitlement?.state === ENTITLEMENT_STATE_BLOCKED ||
  entitlement?.state === ENTITLEMENT_STATE_INELIGIBLE;

// A namespace has picked a trial or paid add-on once its entitlement moves past
// `trial_eligible`; `blocked` counts because it can only follow a trial or a
// subscription that lapsed. Nothing has been selected while the entitlement is
// unresolved, `trial_eligible`, or `ineligible`.
export const hasSelectedTrialOrPaidAddOn = (entitlement) =>
  Boolean(entitlement) &&
  entitlement.state !== ENTITLEMENT_STATE_TRIAL_ELIGIBLE &&
  entitlement.state !== ENTITLEMENT_STATE_INELIGIBLE;

export const formatGraphQLError = (errorString, defaultMessage) => {
  if (typeof errorString === 'string' && errorString.length > 0) {
    return errorString.replace('GraphQL error: ', '');
  }

  return (
    defaultMessage ||
    s__('SecretsManager|An error occurred while fetching secrets manager data. Please try again.')
  );
};
