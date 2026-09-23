import { updateHistory, setUrlParams, removeParams, queryToObject } from '~/lib/utils/url_utility';
import { DETAIL_VIEW_QUERY_PARAM_NAME } from '~/work_items/constants';
import { WORKPLAN_PANEL_URL_VALUE, WORKPLAN_STATE_PARAM, WORKPLAN_STATE_EDIT } from './constants';

const currentShowParam = () =>
  queryToObject(window.location.search)?.[DETAIL_VIEW_QUERY_PARAM_NAME];

export const parseWorkplanUrlState = (search = window.location.search) => {
  const params = queryToObject(search);
  const requestsPanel = params?.[DETAIL_VIEW_QUERY_PARAM_NAME] === WORKPLAN_PANEL_URL_VALUE;
  return {
    requestsPanel,
    requestsEdit: requestsPanel && params?.[WORKPLAN_STATE_PARAM] === WORKPLAN_STATE_EDIT,
  };
};

export const buildWorkplanUrl = ({ editing = false } = {}) => {
  const params = { [DETAIL_VIEW_QUERY_PARAM_NAME]: WORKPLAN_PANEL_URL_VALUE };
  params[WORKPLAN_STATE_PARAM] = editing ? WORKPLAN_STATE_EDIT : null;
  return setUrlParams(params);
};

// The drawer opens the plan by navigating to the standalone work item page.
// workItemWebUrl is relative, so build the query string directly rather than
// through setUrlParams, which cannot parse a relative URL.
export const buildWorkplanPageUrl = (base, { editing = false } = {}) => {
  const query = `${DETAIL_VIEW_QUERY_PARAM_NAME}=${WORKPLAN_PANEL_URL_VALUE}`;
  const editParam = editing ? `&${WORKPLAN_STATE_PARAM}=${WORKPLAN_STATE_EDIT}` : '';
  return `${base}?${query}${editParam}`;
};

export const writeWorkplanUrl = ({ editing = false } = {}) => {
  // Skip if the URL already encodes this state, to avoid a duplicate history entry.
  const { requestsPanel, requestsEdit } = parseWorkplanUrlState();
  if (requestsPanel && requestsEdit === editing) {
    return;
  }
  updateHistory({ url: buildWorkplanUrl({ editing }) });
};

export const clearWorkplanUrl = () => {
  // Only strip if we still own ?show; another panel may have overwritten it.
  if (currentShowParam() !== WORKPLAN_PANEL_URL_VALUE) {
    return;
  }
  updateHistory({
    url: removeParams([DETAIL_VIEW_QUERY_PARAM_NAME, WORKPLAN_STATE_PARAM]),
  });
};
