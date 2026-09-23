import { convertToCamelCase } from '~/lib/utils/text_utility';
import { REPLICABLE_GROUP_TITLES } from '../constants';

const compareReplicableTypes = (a, b) => {
  if (a.dataTypeSortOrder === b.dataTypeSortOrder) {
    return a.name.localeCompare(b.name);
  }

  return a.dataTypeSortOrder - b.dataTypeSortOrder;
};

export const sortedReplicableTypes = (state) => {
  return [...state.replicableTypes].sort(compareReplicableTypes);
};

const buildReplicableGroup = (replicableGroup, children) => {
  const [{ dataType, dataTypeTitle, dataTypeSortOrder }] = children;

  return {
    dataType,
    dataTypeTitle,
    dataTypeSortOrder,
    name: replicableGroup,
    namePlural: replicableGroup,
    titlePlural: REPLICABLE_GROUP_TITLES[replicableGroup],
    replicationEnabled: children.some((child) => child.replicationEnabled),
    verificationEnabled: children.some((child) => child.verificationEnabled),
    replicableGroup: null,
    children,
  };
};

export const groupedReplicableTypes = (_, getters) => {
  const replicableTypes = getters.sortedReplicableTypes;

  // While the legacy replicable sharing the group's key is still enabled (dual-run),
  // grouping would render two rows with the same title, so keep its partitions flat.
  const isSuppressed = (replicableGroup) =>
    replicableTypes.some((replicable) => replicable.namePlural === replicableGroup);

  return replicableTypes
    .reduce((acc, replicable) => {
      const { replicableGroup } = replicable;

      if (!replicableGroup || isSuppressed(replicableGroup)) {
        return [...acc, replicable];
      }

      if (acc.some((entry) => entry.children && entry.namePlural === replicableGroup)) {
        return acc;
      }

      const children = replicableTypes.filter((r) => r.replicableGroup === replicableGroup);

      return [...acc, buildReplicableGroup(replicableGroup, children)];
    }, [])
    .sort(compareReplicableTypes);
};

const aggregateValues = (valuesList) => {
  const enabledValues = valuesList.filter(Boolean);

  if (!enabledValues.length) {
    return null;
  }

  return enabledValues.reduce(
    (acc, values) => ({
      total: acc.total + (Number(values.total) || 0),
      success: acc.success + (Number(values.success) || 0),
      failed: acc.failed + (Number(values.failed) || 0),
    }),
    { total: 0, success: 0, failed: 0 },
  );
};

const groupInfo = (flatInfo, groupedTypes, enabledKey) => {
  const infoFor = ({ namePlural }) => flatInfo.find((info) => info.namePlural === namePlural);

  return groupedTypes.map((replicable) => {
    if (!replicable.children) {
      return infoFor(replicable);
    }

    const children = replicable.children.map(infoFor);
    const { dataType, dataTypeTitle, namePlural, titlePlural } = replicable;

    return {
      dataType,
      dataTypeTitle,
      namePlural,
      titlePlural,
      [enabledKey]: replicable[enabledKey],
      values: aggregateValues(children.map((child) => child.values)),
      children,
    };
  });
};

export const verificationInfo = (state, getters) => (id) => {
  const site = state.sites.find((n) => n.id === id);
  const variables = {};

  if (site.primary) {
    variables.total = 'ChecksumTotalCount';
    variables.success = 'ChecksummedCount';
    variables.failed = 'ChecksumFailedCount';
  } else {
    variables.total = 'VerificationTotalCount';
    variables.success = 'VerifiedCount';
    variables.failed = 'VerificationFailedCount';
  }

  return getters.sortedReplicableTypes.map(
    ({
      namePlural,
      dataType,
      dataTypeTitle,
      titlePlural,
      dataManagementUrl,
      verificationEnabled,
    }) => {
      const camelCaseName = convertToCamelCase(namePlural);
      const values = verificationEnabled
        ? {
            total: site[`${camelCaseName}${variables.total}`],
            success: site[`${camelCaseName}${variables.success}`],
            failed: site[`${camelCaseName}${variables.failed}`],
          }
        : null;

      return {
        dataType,
        dataTypeTitle,
        namePlural,
        titlePlural,
        dataManagementUrl,
        verificationEnabled,
        values,
      };
    },
  );
};

export const syncInfo = (state, getters) => (id) => {
  const site = state.sites.find((n) => n.id === id);

  return getters.sortedReplicableTypes.map(
    ({ namePlural, dataType, dataTypeTitle, titlePlural, replicationEnabled }) => {
      const camelCaseName = convertToCamelCase(namePlural);
      const values = replicationEnabled
        ? {
            total: site[`${camelCaseName}Count`],
            success: site[`${camelCaseName}SyncedCount`],
            failed: site[`${camelCaseName}FailedCount`],
          }
        : null;

      return {
        dataType,
        dataTypeTitle,
        namePlural,
        titlePlural,
        replicationEnabled,
        values,
      };
    },
  );
};

export const groupedVerificationInfo = (_, getters) => (id) =>
  groupInfo(getters.verificationInfo(id), getters.groupedReplicableTypes, 'verificationEnabled');

export const groupedSyncInfo = (_, getters) => (id) =>
  groupInfo(getters.syncInfo(id), getters.groupedReplicableTypes, 'replicationEnabled');

export const dataTypes = (_, getters) => {
  return getters.sortedReplicableTypes.reduce((acc, replicable) => {
    if (acc.some((type) => type.dataType === replicable.dataType)) {
      return acc;
    }

    return [
      ...acc,
      {
        dataType: replicable.dataType,
        dataTypeTitle: replicable.dataTypeTitle,
      },
    ];
  }, []);
};

export const replicationCountsByDataTypeForSite = (_, getters) => (id) => {
  const syncInfoData = getters.syncInfo(id);
  const verificationInfoData = getters.verificationInfo(id);

  return getters.dataTypes.map(({ dataType, dataTypeTitle }) => {
    return {
      dataType,
      dataTypeTitle,
      sync: syncInfoData
        .filter((replicable) => replicable.dataType === dataType)
        .map((d) => d.values),
      verification: verificationInfoData
        .filter((replicable) => replicable.dataType === dataType)
        .map((d) => d.values),
    };
  });
};

export const canRemoveSite = (state) => (id) => {
  const site = state.sites.find((n) => n.id === id);

  return !site.primary || state.sites.length === 1;
};

const filterByStatus = (status) => {
  if (!status) {
    return () => true;
  }

  // If the healthStatus is not falsey, we group that as status "unknown"
  return (n) => (n.healthStatus ? n.healthStatus.toLowerCase() === status : status === 'unknown');
};

const filterBySearch = (search) => {
  if (!search) {
    return () => true;
  }

  return (n) =>
    n.name?.toLowerCase().includes(search.toLowerCase()) ||
    n.url?.toLowerCase().includes(search.toLowerCase());
};

export const filteredSites = (state) => {
  return state.sites
    .filter(filterByStatus(state.statusFilter))
    .filter(filterBySearch(state.searchFilter));
};

export const countSitesForStatus = (state) => (status) => {
  return state.sites.filter(filterByStatus(status)).length;
};

export const siteHasVersionMismatch = (state) => (id) => {
  const site = state.sites.find((n) => n.id === id);
  const primarySite = state.sites.find((n) => n.primary);

  return site?.version !== primarySite?.version || site?.revision !== primarySite?.revision;
};
