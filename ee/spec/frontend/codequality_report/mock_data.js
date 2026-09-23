import mockGetCodeQualityViolationsResponse from 'test_fixtures/graphql/codequality_report/graphql/queries/get_code_quality_violations.query.graphql.json';

export { mockGetCodeQualityViolationsResponse };

export const codeQualityViolations =
  mockGetCodeQualityViolationsResponse.data.project.pipeline.codeQualityReports;
