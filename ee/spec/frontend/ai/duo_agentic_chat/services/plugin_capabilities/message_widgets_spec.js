import { messageWidgets } from 'ee/ai/duo_agentic_chat/services/plugin_capabilities/message_widgets';

describe('messageWidgets capability', () => {
  const component = { name: 'SomeWidget' };
  const validWidget = { matchMessage: () => true, component };

  it('is filed under the `messageWidgets` plugin key', () => {
    expect(messageWidgets.key).toBe('messageWidgets');
  });

  describe('validate', () => {
    it('accepts a minimal widget', () => {
      expect(messageWidgets.validate(validWidget)).toEqual([]);
    });

    it('accepts every optional field at once', () => {
      expect(
        messageWidgets.validate({
          ...validWidget,
          defaultProps: () => ({}),
          layout: 'pinned',
          groupable: false,
        }),
      ).toEqual([]);
    });

    it.each([null, undefined, 'widget', 7])('rejects %p as a widget', (widget) => {
      expect(messageWidgets.validate(widget)).toEqual(['must be an object']);
    });

    it.each`
      description                      | widget                                      | error
      ${'a missing matchMessage'}      | ${{ component }}                            | ${'`matchMessage` must be a function'}
      ${'a non-function matchMessage'} | ${{ ...validWidget, matchMessage: 'nope' }} | ${'`matchMessage` must be a function'}
      ${'a missing component'}         | ${{ matchMessage: () => true }}             | ${'`component` must be a Vue component'}
      ${'a null component'}            | ${{ ...validWidget, component: null }}      | ${'`component` must be a Vue component'}
      ${'a string defaultProps'}       | ${{ ...validWidget, defaultProps: 'nope' }} | ${'`defaultProps` must be a function or an object'}
      ${'an unknown layout'}           | ${{ ...validWidget, layout: 'floating' }}   | ${'`layout` must be one of: inline, pinned'}
      ${'a non-boolean groupable'}     | ${{ ...validWidget, groupable: 'yes' }}     | ${'`groupable` must be a boolean'}
    `('reports $description', ({ widget, error }) => {
      expect(messageWidgets.validate(widget)).toEqual([error]);
    });

    it('reports every violation at once', () => {
      expect(messageWidgets.validate({ layout: 'floating' })).toEqual([
        '`matchMessage` must be a function',
        '`component` must be a Vue component',
        '`layout` must be one of: inline, pinned',
      ]);
    });
  });

  describe('resolve', () => {
    it('returns an empty array when there are no plugins', () => {
      expect(messageWidgets.resolve([])).toEqual([]);
    });

    it('skips plugins that contribute no widgets', () => {
      expect(messageWidgets.resolve([{}, { messageWidgets: [validWidget] }])).toEqual([
        validWidget,
      ]);
    });

    it('leaves a widget without defaultProps untouched', () => {
      const dependencies = { apollo: {}, duoChatContext: { projectId: 'gid://gitlab/Project/1' } };

      expect(messageWidgets.resolve([{ messageWidgets: [validWidget] }], dependencies)).toEqual([
        validWidget,
      ]);
    });

    it('leaves an object defaultProps untouched', () => {
      const widget = { ...validWidget, defaultProps: { message: {} } };

      expect(messageWidgets.resolve([{ messageWidgets: [widget] }], { apollo: {} })).toEqual([
        widget,
      ]);
    });

    describe('when a widget declares a function defaultProps', () => {
      const dependencies = { apollo: {}, duoChatContext: { projectId: 'gid://gitlab/Project/1' } };
      const defaultProps = jest.fn(() => ({ some: 'props' }));
      let resolved;

      beforeEach(() => {
        defaultProps.mockClear();
        [resolved] = messageWidgets.resolve(
          [{ messageWidgets: [{ ...validWidget, defaultProps }] }],
          dependencies,
        );
      });

      // duo-ui only ever passes (message, workingDirectory), so a widget that needs the
      // chat's context can read it nowhere else.
      it('appends the dependencies to the arguments duo-ui passes', () => {
        const message = { id: 1 };

        expect(resolved.defaultProps(message, '/work/dir')).toEqual({ some: 'props' });
        expect(defaultProps).toHaveBeenCalledWith(message, '/work/dir', dependencies);
      });

      it('leaves the rest of the descriptor alone', () => {
        expect(resolved).toMatchObject({
          matchMessage: validWidget.matchMessage,
          component,
        });
      });
    });

    it('passes an empty object when resolved without dependencies', () => {
      const defaultProps = jest.fn();
      const [resolved] = messageWidgets.resolve([
        { messageWidgets: [{ ...validWidget, defaultProps }] },
      ]);

      resolved.defaultProps({ id: 1 }, '/work/dir');

      expect(defaultProps).toHaveBeenCalledWith({ id: 1 }, '/work/dir', {});
    });

    it('flattens widgets across plugins, preserving registration order', () => {
      const first = { ...validWidget, component: { name: 'First' } };
      const second = { ...validWidget, component: { name: 'Second' } };
      const third = { ...validWidget, component: { name: 'Third' } };

      expect(
        messageWidgets.resolve([{ messageWidgets: [first, second] }, { messageWidgets: [third] }]),
      ).toEqual([first, second, third]);
    });
  });
});
