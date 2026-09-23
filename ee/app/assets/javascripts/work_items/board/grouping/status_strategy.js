import { s__ } from '~/locale';
import { sortStatuses } from 'ee/work_items/utils';
import getBoardNamespaceStatusesQuery from 'ee_else_ce/work_items/board/graphql/get_namespace_statuses.query.graphql';
import namespaceWorkItemTypesQuery from '~/work_items/graphql/namespace_work_item_types.query.graphql';
import { WIDGET_TYPE_STATUS } from '~/work_items/constants';
import {
  findStatusWidget,
  getWorkItemTypeAllowedStatusMap,
  isStatusWidget,
} from '~/work_items/utils';

// Statuses don't exist in CE, so this real strategy only ships in EE.
/** @type {import('~/work_items/board/grouping/index').GroupingStrategy} */
export const statusStrategy = {
  property: 'status',

  label: s__('WorkItems|Status'),

  valuesQuery: getBoardNamespaceStatusesQuery,

  // Sort by category (triage, to_do, in_progress, done, cancelled) so columns
  // show in a consistent order instead of however the API happens to return them.
  extractValues(data) {
    return sortStatuses(data?.namespace?.rootNamespace?.statuses?.nodes ?? []);
  },

  groupFilter(value) {
    return { status: { name: value.name } };
  },

  itemValueId(item) {
    return findStatusWidget(item)?.status?.id ?? null;
  },

  moveInput(value) {
    return { statusWidget: { status: value.id } };
  },

  // The column value already has the status fields the draft expects ({ id, name, ... }).
  newItemDraft(value) {
    return { [WIDGET_TYPE_STATUS]: { status: value } };
  },

  patchCard(node, value) {
    const statusWidget = findStatusWidget(node);
    if (statusWidget) {
      // Spread the old status first so any fields the column value doesn't carry
      // (it might be a partial object) don't get wiped out.
      statusWidget.status = { ...statusWidget.status, ...value };
    }
  },

  headerDecoration(value) {
    return value.iconName
      ? { type: 'icon', name: value.iconName, color: value.color }
      : { type: 'none' };
  },

  // A work item type's Status widget can limit which statuses it's allowed to take.
  // In CE, `allowedStatuses` isn't there, so the map ends up empty and every drop is allowed.
  gateQuery: namespaceWorkItemTypesQuery,

  extractGateData(data) {
    const workItemTypes = data?.namespace?.workItemTypes?.nodes ?? [];
    return {
      allowedStatusesByTypeId: getWorkItemTypeAllowedStatusMap(workItemTypes),
      typeNamesWithStatus: workItemTypes
        .filter((type) => type.widgetDefinitions?.some(isStatusWidget))
        .map((type) => type.name),
    };
  },

  isDropAllowed({ item, value, gateData }) {
    const allowedStatuses = gateData?.allowedStatusesByTypeId?.[item?.workItemType?.id];
    // No constraint recorded for this type (CE, or a type with no status widget): allow it.
    if (!allowedStatuses) {
      return true;
    }
    return allowedStatuses.some((status) => status.id === value.id);
  },

  // Unlike isDropAllowed, this answers "no" until the gate data lands. Callers use it
  // to decide whether to offer creating a type, and offering then withdrawing a button
  // is worse than it appearing a beat late.
  supportsWorkItemType({ typeName, gateData }) {
    return Boolean(gateData?.typeNamesWithStatus?.includes(typeName));
  },
};
