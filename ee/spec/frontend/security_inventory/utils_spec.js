import {
  getVulnerabilityTotal,
  securityScannerOfProjectValidator,
  itemValidator,
  securityScannerOfGroupValidator,
  aggregateAnalyzerStatuses,
  visibleToggleableColumns,
  filterQueryVariables,
  toolCoverageFilterVariables,
} from 'ee/security_inventory/utils';
import {
  TOGGLEABLE_COLUMNS,
  SECURITY_ATTRIBUTES_COLUMN,
  STATUS_FILTER_KEYS,
} from 'ee/security_inventory/constants';

jest.mock('ee/security_inventory/utils', () => {
  const originalModule = jest.requireActual('ee/security_inventory/utils');
  return {
    ...originalModule,
    securityScannerOfProjectValidator: jest.fn(originalModule.securityScannerOfProjectValidator),
  };
});

describe('visibleToggleableColumns', () => {
  it('offers every toggleable column when the user can read attributes', () => {
    expect(visibleToggleableColumns(true)).toEqual(TOGGLEABLE_COLUMNS);
  });

  it('omits the security attributes column when the user cannot read attributes', () => {
    const columns = visibleToggleableColumns(false);

    expect(columns).not.toContain(SECURITY_ATTRIBUTES_COLUMN);
    expect(columns).toEqual(
      TOGGLEABLE_COLUMNS.filter((column) => column.key !== SECURITY_ATTRIBUTES_COLUMN.key),
    );
  });
});

describe('getVulnerabilityTotal', () => {
  it('should return 0 when no vulnerabilities are provided', () => {
    const result = getVulnerabilityTotal();
    expect(result).toBe(0);
  });

  it('should return the correct total when given specific vulnerability counts', () => {
    const vulnerabilityCounts = {
      critical: 3,
      high: 5,
      medium: 2,
      low: 1,
      info: 0,
      unknown: 4,
    };
    const result = getVulnerabilityTotal(vulnerabilityCounts);
    expect(result).toBe(15);
  });

  it('should handle missing fields by defaulting to 0', () => {
    const vulnerabilityCounts = {
      critical: 3,
      high: 2,
      medium: 1,
    };
    const result = getVulnerabilityTotal(vulnerabilityCounts);
    expect(result).toBe(6);
  });

  it('should return 0 when passed an empty object', () => {
    const result = getVulnerabilityTotal({});
    expect(result).toBe(0);
  });
});

describe('securityScannerOfGroupValidator', () => {
  const item = {
    analyzerType: 'DEPENDENCY_SCANNING',
    failure: 1,
    notConfigured: 3,
    success: 2,
    updatedAt: undefined,
  };

  describe('basic object validation', () => {
    it('returns false for non-object types', () => {
      expect(securityScannerOfGroupValidator(123)).toBe(false);
      expect(securityScannerOfGroupValidator('string')).toBe(false);
      expect(securityScannerOfGroupValidator([])).toBe(false);
      expect(securityScannerOfGroupValidator(null)).toBe(false);
      expect(securityScannerOfGroupValidator('')).toBe(false);
      expect(securityScannerOfGroupValidator({})).toBe(false);
    });
  });

  describe('props validation', () => {
    it.each`
      description                     | value                                | expected
      ${'analyzerType is a number'}   | ${{ ...item, analyzerType: 5 }}      | ${false}
      ${'analyzerType is undefined'}  | ${{ ...item, analyzerType: {} }}     | ${false}
      ${'analyzerType is a string'}   | ${{ ...item, analyzerType: 'SAST' }} | ${true}
      ${'analyzerType is a null'}     | ${{ ...item, analyzerType: null }}   | ${false}
      ${'failure is a number'}        | ${{ ...item, failure: 5 }}           | ${true}
      ${'failure is undefined'}       | ${{ ...item, failure: {} }}          | ${false}
      ${'failure is a string'}        | ${{ ...item, failure: '5' }}         | ${false}
      ${'failure is a null'}          | ${{ ...item, failure: null }}        | ${false}
      ${'notConfigured is a number'}  | ${{ ...item, notConfigured: 5 }}     | ${true}
      ${'notConfigured is undefined'} | ${{ ...item, notConfigured: {} }}    | ${false}
      ${'notConfigured is a string'}  | ${{ ...item, notConfigured: '5' }}   | ${false}
      ${'notConfigured is a null'}    | ${{ ...item, notConfigured: null }}  | ${false}
      ${'success is a number'}        | ${{ ...item, success: 5 }}           | ${true}
      ${'success is undefined'}       | ${{ ...item, success: {} }}          | ${false}
      ${'success is a string'}        | ${{ ...item, success: '5' }}         | ${false}
      ${'success is a null'}          | ${{ ...item, success: null }}        | ${false}
    `('$description', ({ value, expected }) => {
      const result = securityScannerOfGroupValidator(value);
      expect(result).toBe(expected);
    });
  });

  describe('complex scenarios', () => {
    it('returns false when any validation fails', () => {
      const invalidItems = [
        { analyzerType: 'SAST' },
        {
          analyzerType: 'SAST',
          notConfigured: 3,
          success: 2,
        },
        {
          failure: 1,
          notConfigured: 3,
          success: 2,
        },
        {
          analyzerType: 2,
          failure: 1,
          notConfigured: 3,
          success: 2,
        },
      ];
      invalidItems.forEach((invalidItem) => {
        expect(securityScannerOfGroupValidator(invalidItem)).toBe(false);
      });
    });

    it('allows additional properties', () => {
      const itemWithUnexpectedProps = {
        analyzerType: 'SAST',
        failure: 1,
        notConfigured: 3,
        success: 2,
        unexpectedProp: 'value',
      };
      expect(securityScannerOfGroupValidator(itemWithUnexpectedProps)).toBe(true);
    });
  });
});

describe('securityScannerOfProjectValidator', () => {
  describe('valid scenarios', () => {
    it('returns true for an array with minimal valid objects', () => {
      const validInput = [{ analyzerType: 'SAST' }];
      expect(securityScannerOfProjectValidator(validInput)).toBe(true);
    });

    it('returns true for an array with complete valid objects', () => {
      const validInput = [
        {
          analyzerType: 'SAST',
          status: 'SUCCESS',
          buildId: 'gid://git/path/123',
          lastCall: '2025-01-01T00:00:00Z',
          updatedAt: '2025-01-01T00:00:00Z',
        },
      ];
      expect(securityScannerOfProjectValidator(validInput)).toBe(true);
    });

    it('returns true for an array with multiple valid objects', () => {
      const validInput = [
        { analyzerType: 'SAST' },
        {
          analyzerType: 'DAST',
          status: 'FAILED',
          buildId: 'gid://git/path/123',
        },
      ];
      expect(securityScannerOfProjectValidator(validInput)).toBe(true);
    });

    it('handles objects with additional unexpected properties', () => {
      const inputWithExtraProps = [
        {
          analyzerType: 'SAST',
          unexpectedProp: 'value',
          status: 'SUCCESS',
        },
      ];
      expect(securityScannerOfProjectValidator(inputWithExtraProps)).toBe(true);
    });

    it('returns true for an empty array', () => {
      expect(securityScannerOfProjectValidator([])).toBe(true);
    });
  });

  describe('invalid scenarios', () => {
    it('returns false when object is missing analyzerType', () => {
      const invalidInput = [{ status: 'SUCCESS' }];
      expect(securityScannerOfProjectValidator(invalidInput)).toBe(false);
    });

    it('returns false when analyzerType is not a string', () => {
      const invalidInput = [{ analyzerType: 123 }];
      expect(securityScannerOfProjectValidator(invalidInput)).toBe(false);
    });

    it('returns false when status is not a string', () => {
      const invalidInput = [
        {
          analyzerType: 'SAST',
          status: 123,
        },
      ];
      expect(securityScannerOfProjectValidator(invalidInput)).toBe(false);
    });

    it('returns false when buildId is not a string', () => {
      const invalidInput = [
        {
          analyzerType: 'SAST',
          buildId: 123,
        },
      ];
      expect(securityScannerOfProjectValidator(invalidInput)).toBe(false);
    });

    it('returns false when lastCall is not a string', () => {
      const invalidInput = [
        {
          analyzerType: 'SAST',
          lastCall: 123,
        },
      ];
      expect(securityScannerOfProjectValidator(invalidInput)).toBe(false);
    });

    it('returns false when updatedAt is not a string', () => {
      const invalidInput = [
        {
          analyzerType: 'SAST',
          updatedAt: 123,
        },
      ];
      expect(securityScannerOfProjectValidator(invalidInput)).toBe(false);
    });

    it('returns false for non-object items', () => {
      const invalidInput = ['not an object', { analyzerType: 'SAST' }];
      expect(securityScannerOfProjectValidator(invalidInput)).toBe(false);
    });

    it('handles multiple objects with mixed validity', () => {
      const mixedInput = [{ analyzerType: 'SAST' }, { status: 'SUCCESS' }];
      expect(securityScannerOfProjectValidator(mixedInput)).toBe(false);
    });
  });
});

describe('itemValidator', () => {
  describe('basic object validation', () => {
    it('returns false for non-object types', () => {
      expect(itemValidator(123)).toBe(false);
      expect(itemValidator('string')).toBe(false);
      expect(itemValidator([])).toBe(false);
      expect(itemValidator(null)).toBe(false);
    });

    it('returns true for an empty object', () => {
      expect(itemValidator({})).toBe(true);
    });
  });

  describe('analyzerStatuses validation', () => {
    it('returns true when analyzerStatuses is a valid array', () => {
      const validAnalyzerStatuses = [{ analyzerType: 'SAST' }];
      securityScannerOfProjectValidator.mockReturnValue(true);
      const item = { analyzerStatuses: validAnalyzerStatuses };
      expect(itemValidator(item)).toBe(true);
    });

    it('returns false when analyzerStatuses is not an array', () => {
      const item = { analyzerStatuses: 'not an array' };
      expect(itemValidator(item)).toBe(false);
    });

    it('returns false when securityScannerOfProjectValidator fails', () => {
      const invalidAnalyzerStatuses = [{ invalid: 'object' }];
      securityScannerOfProjectValidator.mockReturnValue(false);
      const item = { analyzerStatuses: invalidAnalyzerStatuses };
      expect(itemValidator(item)).toBe(false);
    });
  });

  describe('path validation', () => {
    it('returns true when path is a string', () => {
      const item = { path: 'valid/path' };
      expect(itemValidator(item)).toBe(true);
    });

    it('returns false when path is not a string', () => {
      const invalidItems = [{ path: 123 }, { path: null }, { path: {} }];
      invalidItems.forEach((item) => {
        expect(itemValidator(item)).toBe(false);
      });
    });
  });

  describe('webUrl validation', () => {
    it('returns true when webUrl is a string', () => {
      const item = { webUrl: 'https://example.com' };
      expect(itemValidator(item)).toBe(true);
    });

    it('returns false when webUrl is not a string', () => {
      const invalidItems = [{ webUrl: 123 }, { webUrl: null }, { webUrl: {} }];
      invalidItems.forEach((item) => {
        expect(itemValidator(item)).toBe(false);
      });
    });
  });

  describe('complex scenarios', () => {
    it('returns true for an object with multiple valid properties', () => {
      const validItem = {
        path: 'valid/path',
        webUrl: 'https://example.com',
        analyzerStatuses: [{ analyzerType: 'SAST' }],
      };
      securityScannerOfProjectValidator.mockReturnValue(true);
      expect(itemValidator(validItem)).toBe(true);
    });

    it('returns false when any validation fails', () => {
      const invalidItems = [
        { path: 123, webUrl: 'https://example.com' },
        { path: 'valid/path', webUrl: 123 },
        {
          path: 'valid/path',
          webUrl: 'https://example.com',
          analyzerStatuses: [{ invalid: 'object' }],
        },
      ];
      invalidItems.forEach((item) => {
        if (item.analyzerStatuses) {
          securityScannerOfProjectValidator.mockReturnValue(false);
        }
        expect(itemValidator(item)).toBe(false);
      });
    });

    it('allows additional properties', () => {
      const itemWithUnexpectedProps = {
        path: 'valid/path',
        webUrl: 'https://example.com',
        unexpectedProp: 'value',
      };
      expect(itemValidator(itemWithUnexpectedProps)).toBe(true);
    });
  });
});

describe('aggregateAnalyzerStatuses', () => {
  const statusFor = (analyzerType, counts = {}) => ({
    analyzerType,
    success: 0,
    failure: 0,
    stale: 0,
    notConfigured: 0,
    ...counts,
  });

  it('returns an empty object for no requested types', () => {
    expect(aggregateAnalyzerStatuses([statusFor('SAST')], [])).toEqual({});
  });

  it('combines the counts of the requested types', () => {
    const statuses = [
      statusFor('SAST', { success: 5, failure: 1 }),
      statusFor('DAST', { success: 2, stale: 3 }),
    ];

    expect(aggregateAnalyzerStatuses(statuses, ['SAST', 'DAST'])).toMatchObject({
      success: 7,
      failure: 1,
      stale: 3,
      notConfigured: 0,
    });
  });

  it('returns zero for a type with no matching status', () => {
    expect(aggregateAnalyzerStatuses([], ['DAST'])).toMatchObject({
      success: 0,
      failure: 0,
      stale: 0,
      notConfigured: 0,
    });
  });

  it.each([
    ['SAST', 'SAST_ADVANCED'],
    ['CONTAINER_SCANNING', 'CONTAINER_SCANNING_FOR_REGISTRY'],
  ])('combines %s and its merged %s into one count', (primary, merged) => {
    const statuses = [statusFor(primary, { success: 5 }), statusFor(merged, { success: 5 })];

    expect(aggregateAnalyzerStatuses(statuses, [primary, merged])).toMatchObject({ success: 5 });
  });

  it('reads both secret detection types from one status', () => {
    const statuses = [statusFor('SECRET_DETECTION', { success: 9 })];

    expect(
      aggregateAnalyzerStatuses(statuses, [
        'SECRET_DETECTION_PIPELINE_BASED',
        'SECRET_DETECTION_SECRET_PUSH_PROTECTION',
      ]),
    ).toMatchObject({ success: 9 });
  });

  it('returns the most recent update across statuses', () => {
    const statuses = [
      statusFor('SAST', { updatedAt: '2026-01-01T00:00:00Z' }),
      statusFor('DAST', { updatedAt: '2026-06-01T00:00:00Z' }),
    ];

    expect(aggregateAnalyzerStatuses(statuses, ['SAST', 'DAST']).updatedAt).toBe(
      '2026-06-01T00:00:00Z',
    );
  });

  it('handles missing analyzer statuses', () => {
    expect(aggregateAnalyzerStatuses(undefined, ['SAST'])).toMatchObject({ success: 0 });
  });

  it('returns no counts for fully de-duplicated types', () => {
    expect(
      aggregateAnalyzerStatuses([statusFor('SAST', { success: 5 })], ['SAST_ADVANCED']),
    ).toEqual({
      analyzerType: undefined,
      updatedAt: undefined,
    });
  });
});

describe('toolCoverageFilterVariables', () => {
  it('returns no filters for no status selected', () => {
    expect(toolCoverageFilterVariables({ scanner: 'ALL', status: null })).toEqual({});
    expect(toolCoverageFilterVariables()).toEqual({});
  });

  it.each`
    status              | variables
    ${'SUCCESS'}        | ${{ hasScanners: true }}
    ${'FAILED'}         | ${{ hasFailedOrWarning: true }}
    ${'STALE'}          | ${{ hasStale: true }}
    ${'NOT_CONFIGURED'} | ${{ hasScanners: false }}
  `('falls back to an aggregate boolean for all scanners with $status', ({ status, variables }) => {
    expect(toolCoverageFilterVariables({ scanner: 'ALL', status })).toEqual(variables);
  });

  it.each`
    scanner                  | status
    ${'DAST'}                | ${'FAILED'}
    ${'DEPENDENCY_SCANNING'} | ${'FAILED'}
    ${'SAST_IAC'}            | ${'FAILED'}
    ${'SAST'}                | ${'SUCCESS'}
    ${'SECRET_DETECTION'}    | ${'SUCCESS'}
    ${'CONTAINER_SCANNING'}  | ${'SUCCESS'}
  `('returns a $status filter for $scanner', ({ scanner, status }) => {
    expect(toolCoverageFilterVariables({ scanner, status })).toEqual({
      securityAnalyzerFilters: [{ analyzerType: scanner, status }],
    });
  });

  it('returns no filters for an unrecognised scanner', () => {
    expect(toolCoverageFilterVariables({ scanner: 'NOPE', status: 'SUCCESS' })).toEqual({});
  });
});

describe('filterQueryVariables', () => {
  const noStatusFilters = Object.fromEntries(STATUS_FILTER_KEYS.map((key) => [key, null]));

  it('returns default filters for empty input', () => {
    expect(filterQueryVariables()).toEqual({
      search: '',
      hasSearch: false,
      securityAnalyzerFilters: [],
      vulnerabilityCountFilters: [],
      attributeFilters: [],
      ...noStatusFilters,
    });
  });

  it('combines the card and search bar analyzer filters', () => {
    const searchBarFilter = { analyzerType: 'DAST', status: 'SUCCESS' };
    const cardFilter = { analyzerType: 'SAST_IAC', status: 'FAILED' };

    const { securityAnalyzerFilters } = filterQueryVariables({
      filters: { securityAnalyzerFilters: [searchBarFilter] },
      toolCoverageVariables: { securityAnalyzerFilters: [cardFilter] },
    });

    expect(securityAnalyzerFilters).toEqual([searchBarFilter, cardFilter]);
  });

  it('applies aggregate variables', () => {
    expect(
      filterQueryVariables({ toolCoverageVariables: { hasFailedOrWarning: true } }),
    ).toMatchObject({
      hasFailedOrWarning: true,
      securityAnalyzerFilters: [],
    });
  });

  it('passes through search, filters and hasSearch', () => {
    expect(
      filterQueryVariables({
        filters: {
          search: 'gitlab',
          vulnerabilityCountFilters: [{ severity: 'CRITICAL' }],
          attributeFilters: [{ id: 1 }],
        },
        hasSearch: true,
      }),
    ).toMatchObject({
      search: 'gitlab',
      hasSearch: true,
      vulnerabilityCountFilters: [{ severity: 'CRITICAL' }],
      attributeFilters: [{ id: 1 }],
    });
  });

  it('sets one status filter true and the rest null', () => {
    const [statusKey] = STATUS_FILTER_KEYS;

    expect(filterQueryVariables({ filters: { [statusKey]: true } })).toMatchObject({
      ...noStatusFilters,
      [statusKey]: true,
    });
  });
});
