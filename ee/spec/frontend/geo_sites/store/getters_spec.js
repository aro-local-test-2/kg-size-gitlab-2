import * as getters from 'ee/geo_sites/store/getters';
import createState from 'ee/geo_sites/store/state';
import {
  MOCK_UNSORTED_REPLICABLE_TYPES,
  MOCK_SORTED_REPLICABLE_TYPES,
  MOCK_SITES,
  MOCK_VERIFICATION_INFO,
  MOCK_SECONDARY_SYNC_INFO,
  MOCK_FILTER_SITES,
  MOCK_PRIMARY_SITE,
  MOCK_SECONDARY_SITE,
  MOCK_DATA_TYPES,
  MOCK_UPLOAD_PARTITION_TYPES,
  MOCK_LEGACY_UPLOAD_TYPE,
  MOCK_UPLOADS_GROUP_TYPE,
} from '../mock_data';

describe('GeoSites Store Getters', () => {
  let state;

  beforeEach(() => {
    state = createState({
      replicableTypes: MOCK_UNSORTED_REPLICABLE_TYPES,
    });
  });

  describe('sortedReplicableTypes', () => {
    it('returns a properly sorted array of replicable types', () => {
      expect(getters.sortedReplicableTypes(state)).toStrictEqual(MOCK_SORTED_REPLICABLE_TYPES);
    });
  });

  describe('groupedReplicableTypes', () => {
    const [designs, repositories, wikis, packageFiles, containerRepositories] =
      MOCK_SORTED_REPLICABLE_TYPES;

    describe('when no replicable belongs to a group', () => {
      it('returns the sorted replicable types unchanged', () => {
        const mockGetters = { sortedReplicableTypes: MOCK_SORTED_REPLICABLE_TYPES };

        expect(getters.groupedReplicableTypes(state, mockGetters)).toStrictEqual(
          MOCK_SORTED_REPLICABLE_TYPES,
        );
      });
    });

    describe('when replicables belong to a group', () => {
      it('folds them into one group entry sorted by the group name', () => {
        const mockGetters = {
          sortedReplicableTypes: [
            designs,
            repositories,
            wikis,
            MOCK_UPLOAD_PARTITION_TYPES[0],
            packageFiles,
            MOCK_UPLOAD_PARTITION_TYPES[1],
            containerRepositories,
          ],
        };

        expect(getters.groupedReplicableTypes(state, mockGetters)).toStrictEqual([
          designs,
          repositories,
          wikis,
          packageFiles,
          MOCK_UPLOADS_GROUP_TYPE,
          containerRepositories,
        ]);
      });
    });

    describe('when the legacy replicable sharing the group key is present', () => {
      it('keeps the grouped replicables flat', () => {
        const sortedReplicableTypes = [
          MOCK_UPLOAD_PARTITION_TYPES[0],
          packageFiles,
          MOCK_UPLOAD_PARTITION_TYPES[1],
          MOCK_LEGACY_UPLOAD_TYPE,
        ];
        const mockGetters = { sortedReplicableTypes };

        expect(getters.groupedReplicableTypes(state, mockGetters)).toStrictEqual(
          sortedReplicableTypes,
        );
      });
    });
  });

  describe.each`
    getterName                   | flatGetterName        | enabledKey
    ${'groupedSyncInfo'}         | ${'syncInfo'}         | ${'replicationEnabled'}
    ${'groupedVerificationInfo'} | ${'verificationInfo'} | ${'verificationEnabled'}
  `('$getterName', ({ getterName, flatGetterName, enabledKey }) => {
    const infoFor = (replicable, values) => ({
      dataType: replicable.dataType,
      dataTypeTitle: replicable.dataTypeTitle,
      namePlural: replicable.namePlural,
      titlePlural: replicable.titlePlural,
      [enabledKey]: replicable[enabledKey],
      values,
    });

    const packageFilesInfo = infoFor(MOCK_SORTED_REPLICABLE_TYPES[3], {
      total: 25,
      success: 25,
      failed: 0,
    });

    const buildGetters = (childValues) => ({
      groupedReplicableTypes: [MOCK_SORTED_REPLICABLE_TYPES[3], MOCK_UPLOADS_GROUP_TYPE],
      [flatGetterName]: () => [
        packageFilesInfo,
        infoFor(MOCK_UPLOAD_PARTITION_TYPES[0], childValues[0]),
        infoFor(MOCK_UPLOAD_PARTITION_TYPES[1], childValues[1]),
      ],
    });

    it('passes ungrouped replicables through and aggregates the enabled children of a group', () => {
      const mockGetters = buildGetters([null, { total: 10, success: 7, failed: 2 }]);

      expect(getters[getterName](state, mockGetters)(MOCK_SECONDARY_SITE.id)).toStrictEqual([
        packageFilesInfo,
        {
          ...infoFor(MOCK_UPLOADS_GROUP_TYPE, { total: 10, success: 7, failed: 2 }),
          children: [
            infoFor(MOCK_UPLOAD_PARTITION_TYPES[0], null),
            infoFor(MOCK_UPLOAD_PARTITION_TYPES[1], { total: 10, success: 7, failed: 2 }),
          ],
        },
      ]);
    });

    it('sums the values of every enabled child', () => {
      const mockGetters = buildGetters([
        { total: 5, success: 1, failed: 1 },
        { total: 10, success: 7, failed: 2 },
      ]);

      expect(getters[getterName](state, mockGetters)(MOCK_SECONDARY_SITE.id)[1].values).toEqual({
        total: 15,
        success: 8,
        failed: 3,
      });
    });

    it('returns null values when no child has values', () => {
      const mockGetters = buildGetters([null, null]);

      expect(getters[getterName](state, mockGetters)(MOCK_SECONDARY_SITE.id)[1].values).toBe(null);
    });
  });

  describe('verificationInfo', () => {
    const mockGetters = {
      sortedReplicableTypes: MOCK_SORTED_REPLICABLE_TYPES,
    };

    beforeEach(() => {
      state.sites = MOCK_SITES;
    });

    describe('on primary site', () => {
      it('returns values based on whether verification is enabled', () => {
        expect(getters.verificationInfo(state, mockGetters)(MOCK_PRIMARY_SITE.id)).toStrictEqual(
          MOCK_VERIFICATION_INFO,
        );
      });
    });

    describe('on secondary site', () => {
      it('returns values based on whether verification is enabled', () => {
        expect(getters.verificationInfo(state, mockGetters)(MOCK_SECONDARY_SITE.id)).toStrictEqual(
          MOCK_VERIFICATION_INFO,
        );
      });
    });
  });

  describe('syncInfo', () => {
    const mockGetters = {
      sortedReplicableTypes: MOCK_SORTED_REPLICABLE_TYPES,
    };

    beforeEach(() => {
      state.sites = MOCK_SITES;
    });

    it('returns values based on whether replication is enabled', () => {
      expect(getters.syncInfo(state, mockGetters)(MOCK_SECONDARY_SITE.id)).toStrictEqual(
        MOCK_SECONDARY_SYNC_INFO,
      );
    });
  });

  describe.each`
    siteToRemove           | sites                    | canRemove
    ${MOCK_PRIMARY_SITE}   | ${[MOCK_PRIMARY_SITE]}   | ${true}
    ${MOCK_PRIMARY_SITE}   | ${MOCK_SITES}            | ${false}
    ${MOCK_SECONDARY_SITE} | ${[MOCK_SECONDARY_SITE]} | ${true}
    ${MOCK_SECONDARY_SITE} | ${MOCK_SITES}            | ${true}
  `(`canRemoveSite`, ({ siteToRemove, sites, canRemove }) => {
    describe(`when site.primary ${siteToRemove.primary} and total sites is ${sites.length}`, () => {
      beforeEach(() => {
        state.sites = sites;
      });

      it(`should return ${canRemove}`, () => {
        expect(getters.canRemoveSite(state)(siteToRemove.id)).toBe(canRemove);
      });
    });
  });

  describe.each`
    status         | search                                     | expectedSites
    ${null}        | ${''}                                      | ${MOCK_FILTER_SITES}
    ${'healthy'}   | ${''}                                      | ${[MOCK_FILTER_SITES[0], MOCK_FILTER_SITES[1]]}
    ${'unhealthy'} | ${''}                                      | ${[MOCK_FILTER_SITES[2]]}
    ${'disabled'}  | ${''}                                      | ${[MOCK_FILTER_SITES[3]]}
    ${'offline'}   | ${''}                                      | ${[MOCK_FILTER_SITES[4]]}
    ${'unknown'}   | ${''}                                      | ${[MOCK_FILTER_SITES[5]]}
    ${null}        | ${MOCK_FILTER_SITES[1].name}               | ${[MOCK_FILTER_SITES[1]]}
    ${null}        | ${MOCK_FILTER_SITES[3].url}                | ${[MOCK_FILTER_SITES[3]]}
    ${'healthy'}   | ${MOCK_FILTER_SITES[0].name}               | ${[MOCK_FILTER_SITES[0]]}
    ${'healthy'}   | ${MOCK_FILTER_SITES[0].name.toUpperCase()} | ${[MOCK_FILTER_SITES[0]]}
    ${'unhealthy'} | ${MOCK_FILTER_SITES[2].url}                | ${[MOCK_FILTER_SITES[2]]}
    ${'unhealthy'} | ${MOCK_FILTER_SITES[2].url.toUpperCase()}  | ${[MOCK_FILTER_SITES[2]]}
    ${'offline'}   | ${'NOT A MATCH'}                           | ${[]}
  `('filteredSites', ({ status, search, expectedSites }) => {
    describe(`when status is ${status} and search is ${search}`, () => {
      beforeEach(() => {
        state.sites = MOCK_FILTER_SITES;
        state.statusFilter = status;
        state.searchFilter = search;
      });

      it('should return the correct filtered array', () => {
        expect(getters.filteredSites(state)).toStrictEqual(expectedSites);
      });
    });
  });

  describe.each`
    status         | expectedCount
    ${'healthy'}   | ${2}
    ${'unhealthy'} | ${1}
    ${'offline'}   | ${1}
    ${'disabled'}  | ${1}
    ${'unknown'}   | ${1}
  `('countSitesForStatus', ({ status, expectedCount }) => {
    describe(`when status is ${status}`, () => {
      beforeEach(() => {
        state.sites = MOCK_FILTER_SITES;
      });

      it(`should return ${expectedCount}`, () => {
        expect(getters.countSitesForStatus(state)(status)).toBe(expectedCount);
      });
    });
  });

  describe('dataTypes', () => {
    const mockGetters = {
      sortedReplicableTypes: MOCK_SORTED_REPLICABLE_TYPES,
    };

    it('returns the expected array of dataTypes based on the replicableTypes', () => {
      expect(getters.dataTypes(state, mockGetters)).toStrictEqual(MOCK_DATA_TYPES);
    });
  });

  describe('replicationCountsByDataTypeForSite', () => {
    const mockDataType1 = { dataType: 'type_1', dataTypeTitle: 'Type 1' };
    const mockDataType2 = { dataType: 'type_2', dataTypeTitle: 'Type 2' };
    const mockValues = { total: 100, success: 100 };

    it.each`
      description                                   | syncInfo                                                                                      | verificationInfo                                                                              | expectedResponse
      ${'with no data'}                             | ${() => []}                                                                                   | ${() => []}                                                                                   | ${[{ dataType: mockDataType1.dataType, dataTypeTitle: mockDataType1.dataTypeTitle, sync: [], verification: [] }, { dataType: mockDataType2.dataType, dataTypeTitle: mockDataType2.dataTypeTitle, sync: [], verification: [] }]}
      ${'with only one dataType sync data'}         | ${() => [{ ...mockDataType1, values: mockValues }]}                                           | ${() => []}                                                                                   | ${[{ dataType: mockDataType1.dataType, dataTypeTitle: mockDataType1.dataTypeTitle, sync: [mockValues], verification: [] }, { dataType: mockDataType2.dataType, dataTypeTitle: mockDataType2.dataTypeTitle, sync: [], verification: [] }]}
      ${'with only one dataType verification data'} | ${() => []}                                                                                   | ${() => [{ ...mockDataType1, values: mockValues }]}                                           | ${[{ dataType: mockDataType1.dataType, dataTypeTitle: mockDataType1.dataTypeTitle, sync: [], verification: [mockValues] }, { dataType: mockDataType2.dataType, dataTypeTitle: mockDataType2.dataTypeTitle, sync: [], verification: [] }]}
      ${'with only one dataType all data'}          | ${() => [{ ...mockDataType1, values: mockValues }]}                                           | ${() => [{ ...mockDataType1, values: mockValues }]}                                           | ${[{ dataType: mockDataType1.dataType, dataTypeTitle: mockDataType1.dataTypeTitle, sync: [mockValues], verification: [mockValues] }, { dataType: mockDataType2.dataType, dataTypeTitle: mockDataType2.dataTypeTitle, sync: [], verification: [] }]}
      ${'with both dataTypes and all data'}         | ${() => [{ ...mockDataType1, values: mockValues }, { ...mockDataType2, values: mockValues }]} | ${() => [{ ...mockDataType1, values: mockValues }, { ...mockDataType2, values: mockValues }]} | ${[{ dataType: mockDataType1.dataType, dataTypeTitle: mockDataType1.dataTypeTitle, sync: [mockValues], verification: [mockValues] }, { dataType: mockDataType2.dataType, dataTypeTitle: mockDataType2.dataTypeTitle, sync: [mockValues], verification: [mockValues] }]}
    `(
      '$description returns the correct response',
      ({ syncInfo, verificationInfo, expectedResponse }) => {
        const mockGetters = {
          dataTypes: [mockDataType1, mockDataType2],
          syncInfo,
          verificationInfo,
        };

        expect(
          getters.replicationCountsByDataTypeForSite(state, mockGetters)(MOCK_PRIMARY_SITE.id),
        ).toStrictEqual(expectedResponse);
      },
    );
  });

  describe('siteHasVersionMismatch', () => {
    const SITE_ID = '9';

    describe.each`
      site                                                                                         | siteHasVersionMismatch
      ${{ id: SITE_ID, version: '1.0.0', revision: 'asdf' }}                                       | ${true}
      ${{ id: SITE_ID, version: MOCK_PRIMARY_SITE.version, revision: 'asdf' }}                     | ${true}
      ${{ id: SITE_ID, version: '1.0.0', revision: MOCK_PRIMARY_SITE.revision }}                   | ${true}
      ${{ id: SITE_ID, version: MOCK_PRIMARY_SITE.version, revision: MOCK_PRIMARY_SITE.revision }} | ${false}
    `('when primary site exists', ({ site, siteHasVersionMismatch }) => {
      describe(`when site version: ${site.version} (${site.revision}) and primary site version: ${MOCK_PRIMARY_SITE.version} (${MOCK_PRIMARY_SITE.revision}) version mismatch is ${siteHasVersionMismatch}`, () => {
        beforeEach(() => {
          state.sites = [site, MOCK_PRIMARY_SITE];
        });

        it(`should return ${siteHasVersionMismatch}`, () => {
          expect(getters.siteHasVersionMismatch(state)(SITE_ID)).toBe(siteHasVersionMismatch);
        });
      });
    });

    describe('when passed in site does not exist', () => {
      beforeEach(() => {
        state.sites = [MOCK_PRIMARY_SITE];
      });

      it('should return true', () => {
        expect(getters.siteHasVersionMismatch(state)(SITE_ID)).toBe(true);
      });
    });

    describe('when primary site does not exist', () => {
      const site = {
        id: SITE_ID,
        version: MOCK_PRIMARY_SITE.version,
        revision: MOCK_PRIMARY_SITE.revision,
      };

      beforeEach(() => {
        state.sites = [site];
      });

      it('should return true', () => {
        expect(getters.siteHasVersionMismatch(state)(SITE_ID)).toBe(true);
      });
    });
  });
});
