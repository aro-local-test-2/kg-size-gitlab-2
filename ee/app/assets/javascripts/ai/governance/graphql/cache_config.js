// The dashboard reads aiGovernanceMetrics from three separate queries that
// agree on `timeframe` and `agentClass`, so Apollo keys them to one cache
// entry. Each selects a disjoint set of fields, and the default behaviour
// replaces the whole object, dropping whichever fields arrived first.
export const cacheConfig = {
  typePolicies: {
    Group: { fields: { aiGovernanceMetrics: { merge: true } } },
    Project: { fields: { aiGovernanceMetrics: { merge: true } } },
  },
};
