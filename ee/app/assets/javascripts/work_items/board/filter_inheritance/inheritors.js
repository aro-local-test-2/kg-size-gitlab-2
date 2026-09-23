import {
  WIDGET_TYPE_HEALTH_STATUS,
  WIDGET_TYPE_ITERATION,
  WIDGET_TYPE_WEIGHT,
} from '~/work_items/constants';
import { HEALTH_STATUS_VALUE_MAP } from 'ee/work_items/constants';
import { TYPENAME_ITERATION } from '~/graphql_shared/constants';
import { convertToGraphQLId, getIdFromGraphQLId } from '~/graphql_shared/utils';
import {
  FILTER_INHERITORS as ceFilterInheritors,
  normalizeFilterValue,
} from '~/work_items/board/filter_inheritance/inheritors';
import searchIterationsQuery from '../graphql/search_iterations.query.graphql';

const HEALTH_STATUSES = Object.keys(HEALTH_STATUS_VALUE_MAP);

/**
 * EE-only inheritors, appended to the CE list. See the CE `inheritors.js` for the
 * `FilterInheritor` shape and how the board consumes this list via `ee_else_ce`.
 */

/** @type {import('~/work_items/board/filter_inheritance/inheritors').FilterInheritor} */
const iterationInheritor = {
  widgetType: WIDGET_TYPE_ITERATION,

  async resolve({ apolloClient, fullPath, isGroup, filters }) {
    const [rawId] = normalizeFilterValue(filters?.iterationId);
    if (!rawId) {
      return {};
    }

    const id = convertToGraphQLId(TYPENAME_ITERATION, getIdFromGraphQLId(rawId));
    const { data } = await apolloClient.query({
      query: searchIterationsQuery,
      variables: { fullPath, isProject: !isGroup, id },
    });

    const iterations = data?.group?.iterations?.nodes ?? data?.project?.iterations?.nodes ?? [];
    const iteration = iterations.find((node) => node.id === id) ?? null;
    return iteration ? { [WIDGET_TYPE_ITERATION]: { iteration } } : {};
  },
};

/** @type {import('~/work_items/board/filter_inheritance/inheritors').FilterInheritor} */
const weightInheritor = {
  widgetType: WIDGET_TYPE_WEIGHT,
  resolve({ filters }) {
    const raw = Array.isArray(filters?.weight) ? filters.weight[0] : filters?.weight;
    if (raw === undefined || raw === null || raw === '') {
      return {};
    }

    const weight = Number(raw);
    return Number.isFinite(weight) ? { [WIDGET_TYPE_WEIGHT]: { weight } } : {};
  },
};

/** @type {import('~/work_items/board/filter_inheritance/inheritors').FilterInheritor} */
const healthStatusInheritor = {
  widgetType: WIDGET_TYPE_HEALTH_STATUS,
  resolve({ filters }) {
    const value = Array.isArray(filters?.healthStatusFilter)
      ? filters.healthStatusFilter[0]
      : filters?.healthStatusFilter;
    if (!HEALTH_STATUSES.includes(value)) {
      return {};
    }

    return { [WIDGET_TYPE_HEALTH_STATUS]: { healthStatus: value } };
  },
};

export const FILTER_INHERITORS = [
  ...ceFilterInheritors,
  iterationInheritor,
  weightInheritor,
  healthStatusInheritor,
];
