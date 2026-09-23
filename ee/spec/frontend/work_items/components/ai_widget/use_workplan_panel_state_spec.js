import {
  parseWorkplanUrlState,
  buildWorkplanUrl,
  buildWorkplanPageUrl,
  writeWorkplanUrl,
  clearWorkplanUrl,
} from 'ee/work_items/components/ai_widget/use_workplan_panel_state';
import * as urlUtility from '~/lib/utils/url_utility';

describe('workplan panel URL state', () => {
  let originalLocation;

  const setLocation = (search) => {
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: {
        ...window.location,
        search,
        href: `http://test.host/group/project/-/work_items/1${search}`,
      },
    });
  };

  beforeEach(() => {
    originalLocation = window.location;
  });

  afterEach(() => {
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: originalLocation,
    });
  });

  describe('parseWorkplanUrlState', () => {
    describe('when show=workplan is absent', () => {
      it('reports the panel is not requested', () => {
        expect(parseWorkplanUrlState('?show=eyJpaWQiOiI0NiJ9')).toEqual({
          requestsPanel: false,
          requestsEdit: false,
        });
      });
    });

    describe('when show=workplan is present', () => {
      it('reports the panel is requested in view mode', () => {
        expect(parseWorkplanUrlState('?show=workplan')).toEqual({
          requestsPanel: true,
          requestsEdit: false,
        });
      });
    });

    describe('when the edit state param is present', () => {
      it('reports the panel is requested in edit mode', () => {
        expect(parseWorkplanUrlState('?show=workplan&workplan_state=edit')).toEqual({
          requestsPanel: true,
          requestsEdit: true,
        });
      });
    });

    describe('when the edit state param is present without the panel', () => {
      it('ignores the edit state', () => {
        expect(parseWorkplanUrlState('?workplan_state=edit')).toEqual({
          requestsPanel: false,
          requestsEdit: false,
        });
      });
    });
  });

  describe('buildWorkplanUrl', () => {
    beforeEach(() => {
      setLocation('');
    });

    it('adds show=workplan for view mode', () => {
      expect(buildWorkplanUrl({ editing: false })).toMatch(/show=workplan/);
      expect(buildWorkplanUrl({ editing: false })).not.toMatch(/workplan_state/);
    });

    it('adds the edit state for edit mode', () => {
      expect(buildWorkplanUrl({ editing: true })).toMatch(/show=workplan/);
      expect(buildWorkplanUrl({ editing: true })).toMatch(/workplan_state=edit/);
    });
  });

  describe('buildWorkplanPageUrl', () => {
    it('appends show=workplan to a relative base for view mode', () => {
      expect(buildWorkplanPageUrl('/group/project/-/work_items/9')).toBe(
        '/group/project/-/work_items/9?show=workplan',
      );
    });

    it('appends the edit state to a relative base for edit mode', () => {
      expect(buildWorkplanPageUrl('/group/project/-/work_items/9', { editing: true })).toBe(
        '/group/project/-/work_items/9?show=workplan&workplan_state=edit',
      );
    });
  });

  describe('writeWorkplanUrl', () => {
    let updateHistorySpy;

    beforeEach(() => {
      updateHistorySpy = jest.spyOn(urlUtility, 'updateHistory').mockImplementation(() => {});
    });

    describe('when the panel is not yet in the URL', () => {
      beforeEach(() => {
        setLocation('');
        writeWorkplanUrl({ editing: false });
      });

      it('writes show=workplan', () => {
        expect(updateHistorySpy).toHaveBeenCalledTimes(1);
        expect(updateHistorySpy.mock.calls[0][0].url).toMatch(/show=workplan/);
      });
    });

    describe('when opening in edit mode', () => {
      beforeEach(() => {
        setLocation('');
        writeWorkplanUrl({ editing: true });
      });

      it('writes the edit state param', () => {
        expect(updateHistorySpy.mock.calls[0][0].url).toMatch(/workplan_state=edit/);
      });
    });

    describe('when the URL already matches the requested state', () => {
      beforeEach(() => {
        setLocation('?show=workplan');
        writeWorkplanUrl({ editing: false });
      });

      it('does not push a duplicate history entry', () => {
        expect(updateHistorySpy).not.toHaveBeenCalled();
      });
    });

    describe('when the state changes from view to edit', () => {
      beforeEach(() => {
        setLocation('?show=workplan');
        writeWorkplanUrl({ editing: true });
      });

      it('writes the new edit state', () => {
        expect(updateHistorySpy).toHaveBeenCalledTimes(1);
        expect(updateHistorySpy.mock.calls[0][0].url).toMatch(/workplan_state=edit/);
      });
    });
  });

  describe('clearWorkplanUrl', () => {
    let updateHistorySpy;

    beforeEach(() => {
      updateHistorySpy = jest.spyOn(urlUtility, 'updateHistory').mockImplementation(() => {});
    });

    describe('when the value still matches', () => {
      beforeEach(() => {
        setLocation('?show=workplan&workplan_state=edit');
        clearWorkplanUrl();
      });

      it('strips both params', () => {
        expect(updateHistorySpy).toHaveBeenCalledTimes(1);
        expect(updateHistorySpy.mock.calls[0][0].url).not.toMatch(/show=/);
        expect(updateHistorySpy.mock.calls[0][0].url).not.toMatch(/workplan_state/);
      });
    });

    describe('when another panel already overwrote the value', () => {
      beforeEach(() => {
        setLocation('?show=eyJpaWQiOiI0NiJ9');
        clearWorkplanUrl();
      });

      it('does not strip the param', () => {
        expect(updateHistorySpy).not.toHaveBeenCalled();
      });
    });

    describe('when no panel param is present', () => {
      beforeEach(() => {
        setLocation('');
        clearWorkplanUrl();
      });

      it('does nothing', () => {
        expect(updateHistorySpy).not.toHaveBeenCalled();
      });
    });
  });
});
