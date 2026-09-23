function cloneResponse(response) {
  return JSON.parse(JSON.stringify(response));
}

export function buildUpdateResponse({
  baseResponse,
  labelsFixture,
  assigneesFixture,
  milestoneFixture,
  iterationNodes = [],
  statusNodes = [],
  input,
  featuresFixture,
  useWorkItemFeatures = false,
}) {
  const { labelsWidget, assigneesWidget, title } = input;

  /**
   * Echoes an EE widget update back in whichever shape the flag asks for.
   *
   * With the flag off the mutation returns `widgets`; with it on it skips `widgets` and
   * returns `features`. It selects the whole WorkItemFeatures fragment, so a partial
   * `features` would replace the cached object with incomplete data and trigger a
   * refetch that undoes the update. The detail fixture is built from that same fragment,
   * so it supplies the full shape to override. Both shapes hold the same widget object,
   * so `fields` applies either way.
   */
  const updateWidget = (widgetType, featureKey, fields) => {
    const response = cloneResponse(baseResponse);
    const { workItem } = response.data.workItemUpdate;

    if (useWorkItemFeatures) {
      delete workItem.widgets;
      workItem.features = cloneResponse(featuresFixture).data.namespace.workItem.features;
      Object.assign(workItem.features[featureKey], fields);
      return response;
    }

    const widget = workItem.widgets.find(({ type }) => type === widgetType);
    if (widget) {
      Object.assign(widget, fields);
    }
    return response;
  };

  if (labelsWidget) {
    const response = cloneResponse(labelsFixture);
    return response;
  }

  if (assigneesWidget) {
    const response = cloneResponse(assigneesFixture);
    return response;
  }

  if (title) {
    const response = cloneResponse(baseResponse);
    response.data.workItemUpdate.workItem.title = title;
    response.data.workItemUpdate.workItem.titleHtml = title;
    return response;
  }

  if (input.confidential !== undefined) {
    const response = cloneResponse(baseResponse);
    response.data.workItemUpdate.workItem.confidential = input.confidential;
    return response;
  }

  // Closing and reopening only move the state, but the mutation selects the whole work
  // item, so this echoes the fixture's own widget values back. A test that changes a
  // widget and then closes the item sees that widget snap back to its seeded value.
  if (input.stateEvent) {
    const response = cloneResponse(baseResponse);
    response.data.workItemUpdate.workItem.state = input.stateEvent === 'CLOSE' ? 'CLOSED' : 'OPEN';
    return response;
  }

  if (input.milestoneWidget) {
    return cloneResponse(milestoneFixture);
  }

  if (input.startAndDueDateWidget) {
    const response = cloneResponse(baseResponse);
    const { widgets } = response.data.workItemUpdate.workItem;
    const dateWidget = widgets.find((w) => w.type === 'START_AND_DUE_DATE');
    if (dateWidget) {
      Object.assign(dateWidget, {
        startDate: input.startAndDueDateWidget.startDate || null,
        dueDate: input.startAndDueDateWidget.dueDate || null,
        isFixed: input.startAndDueDateWidget.isFixed ?? dateWidget.isFixed,
      });
    }
    return response;
  }

  if (input.weightWidget) {
    return updateWidget('WEIGHT', 'weight', { weight: input.weightWidget.weight });
  }

  // Clearing sends `{ healthStatus: null }`, so the widget key is present either way.
  if (input.healthStatusWidget) {
    return updateWidget('HEALTH_STATUS', 'healthStatus', {
      healthStatus: input.healthStatusWidget.healthStatus,
    });
  }

  // Clearing sends `{ iterationId: null }`, so the widget key is present either way.
  if (input.iterationWidget) {
    const { iterationId } = input.iterationWidget;
    // Echoes back the node the dropdown offered, which is what the server would return.
    const iteration = iterationNodes.find(({ id }) => id === iterationId) ?? null;

    return updateWidget('ITERATION', 'iteration', { iteration });
  }

  // The dropdown sends the id of a status the namespace allows, so this echoes back the node
  // it offered, which is what the server would return.
  if (input.statusWidget) {
    const status = statusNodes.find(({ id }) => id === input.statusWidget.status) ?? null;

    return updateWidget('STATUS', 'status', { status });
  }

  return cloneResponse(baseResponse);
}
