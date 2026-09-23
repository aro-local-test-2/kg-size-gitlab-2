export const cdApplicationId = 'gid://gitlab/Cd::Application/1';

export const mockServices = [
  {
    id: 'gid://gitlab/Cd::Service/1',
    name: 'payment-api',
    artifactSources: {
      nodes: [
        {
          id: 'gid://gitlab/Cd::ArtifactSource/1',
          __typename: 'CdArtifactSource',
          sourceRef: 'registry.example.com/payment-api',
          versions: {
            nodes: [
              {
                id: 'gid://gitlab/Cd::Version/1',
                __typename: 'CdVersion',
                name: 'v1.0.0',
                createdAt: '2024-01-01T00:00:00Z',
                verified: true,
              },
              {
                id: 'gid://gitlab/Cd::Version/2',
                __typename: 'CdVersion',
                name: 'v2.0.0',
                createdAt: '2024-03-01T00:00:00Z',
                verified: true,
              },
            ],
          },
        },
      ],
    },
    serviceEnvironmentHealths: {
      nodes: [
        {
          id: 'gid://gitlab/Cd::ServiceEnvironmentHealth/11',
          environment: {
            id: 'gid://gitlab/Cd::Environment/11',
            name: 'production',
            tier: 'PRODUCTION',
          },
          deployedVersions: {
            nodes: [{ id: 'gid://gitlab/Cd::Version/2', __typename: 'CdVersion' }],
          },
        },
      ],
    },
  },
  {
    id: 'gid://gitlab/Cd::Service/2',
    name: 'fraud-detector',
    artifactSources: {
      nodes: [
        {
          id: 'gid://gitlab/Cd::ArtifactSource/2',
          __typename: 'CdArtifactSource',
          sourceRef: 'registry.example.com/fraud-detector',
          versions: {
            nodes: [
              {
                id: 'gid://gitlab/Cd::Version/3',
                __typename: 'CdVersion',
                name: 'v0.9.0',
                createdAt: '2024-02-01T00:00:00Z',
                verified: true,
              },
            ],
          },
        },
      ],
    },
    serviceEnvironmentHealths: { nodes: [] },
  },
];

export const serviceWithoutVersions = {
  id: 'gid://gitlab/Cd::Service/9',
  name: 'legacy-batch',
  artifactSources: { nodes: [] },
  serviceEnvironmentHealths: { nodes: [] },
};

export const serviceWithEmptySource = {
  id: 'gid://gitlab/Cd::Service/8',
  name: 'notifications',
  artifactSources: {
    nodes: [
      {
        id: 'gid://gitlab/Cd::ArtifactSource/8',
        __typename: 'CdArtifactSource',
        sourceRef: 'registry.example.com/notifications',
        versions: { nodes: [] },
      },
    ],
  },
  serviceEnvironmentHealths: { nodes: [] },
};

export const serviceWithVersions = {
  id: 'gid://gitlab/Cd::Service/5',
  name: 'gateway',
  artifactSources: {
    nodes: [
      {
        id: 'gid://gitlab/Cd::ArtifactSource/5',
        __typename: 'CdArtifactSource',
        sourceRef: 'registry.example.com/gateway',
        versions: {
          nodes: [
            {
              id: 'gid://gitlab/Cd::Version/10',
              __typename: 'CdVersion',
              name: 'v1',
              createdAt: '2024-05-01T00:00:00Z',
              verified: true,
            },
            {
              id: 'gid://gitlab/Cd::Version/11',
              __typename: 'CdVersion',
              name: 'v2',
              createdAt: '2024-05-01T00:00:00Z',
              verified: true,
            },
          ],
        },
      },
    ],
  },
  serviceEnvironmentHealths: {
    nodes: [
      {
        id: 'gid://gitlab/Cd::ServiceEnvironmentHealth/1',
        environment: { id: 'gid://gitlab/Cd::Environment/1', name: 'prod-eu', tier: 'PRODUCTION' },
        deployedVersions: {
          nodes: [{ id: 'gid://gitlab/Cd::Version/11', __typename: 'CdVersion' }],
        },
      },
      {
        id: 'gid://gitlab/Cd::ServiceEnvironmentHealth/2',
        environment: { id: 'gid://gitlab/Cd::Environment/2', name: 'prod-us', tier: 'PRODUCTION' },
        deployedVersions: {
          nodes: [{ id: 'gid://gitlab/Cd::Version/11', __typename: 'CdVersion' }],
        },
      },
    ],
  },
};

export const serviceInManyEnvironments = {
  id: 'gid://gitlab/Cd::Service/31',
  name: 'search',
  artifactSources: {
    nodes: [
      {
        id: 'gid://gitlab/Cd::ArtifactSource/31',
        __typename: 'CdArtifactSource',
        sourceRef: 'registry.example.com/search',
        versions: {
          nodes: [
            {
              id: 'gid://gitlab/Cd::Version/31',
              __typename: 'CdVersion',
              name: 'v3.0.0',
              createdAt: '2024-05-01T00:00:00Z',
              verified: true,
            },
          ],
        },
      },
    ],
  },
  serviceEnvironmentHealths: {
    nodes: [
      ['qa', 'QA'],
      ['production', 'PRODUCTION'],
      ['dev', 'DEVELOPMENT'],
      ['staging', 'STAGING'],
    ].map(([name, tier], index) => ({
      id: `gid://gitlab/Cd::ServiceEnvironmentHealth/3${index}`,
      environment: { id: `gid://gitlab/Cd::Environment/3${index}`, name, tier },
      deployedVersions: { nodes: [{ id: 'gid://gitlab/Cd::Version/31', __typename: 'CdVersion' }] },
    })),
  },
};

export const serviceWithMultipleSources = {
  id: 'gid://gitlab/Cd::Service/7',
  name: 'checkout',
  artifactSources: {
    nodes: [
      {
        id: 'gid://gitlab/Cd::ArtifactSource/71',
        __typename: 'CdArtifactSource',
        sourceRef: 'registry.example.com/checkout-amd64',
        versions: {
          nodes: [
            {
              id: 'gid://gitlab/Cd::Version/20',
              __typename: 'CdVersion',
              name: 'v1.0.0',
              createdAt: '2024-04-01T00:00:00Z',
              verified: true,
            },
            {
              id: 'gid://gitlab/Cd::Version/21',
              __typename: 'CdVersion',
              name: 'v1.1.0',
              createdAt: '2024-06-01T00:00:00Z',
              verified: true,
            },
          ],
        },
      },
      {
        id: 'gid://gitlab/Cd::ArtifactSource/72',
        __typename: 'CdArtifactSource',
        sourceRef: 'registry.example.com/checkout-arm64',
        versions: {
          nodes: [
            {
              id: 'gid://gitlab/Cd::Version/22',
              __typename: 'CdVersion',
              name: 'v2.0.0',
              createdAt: '2024-05-01T00:00:00Z',
              verified: true,
            },
          ],
        },
      },
    ],
  },
  serviceEnvironmentHealths: {
    nodes: [
      {
        id: 'gid://gitlab/Cd::ServiceEnvironmentHealth/3',
        environment: { id: 'gid://gitlab/Cd::Environment/3', name: 'prod-eu', tier: 'PRODUCTION' },
        deployedVersions: {
          nodes: [
            { id: 'gid://gitlab/Cd::Version/21', __typename: 'CdVersion' },
            { id: 'gid://gitlab/Cd::Version/22', __typename: 'CdVersion' },
          ],
        },
      },
    ],
  },
};

const DEFAULT_PAGE_INFO = {
  __typename: 'PageInfo',
  hasNextPage: false,
  hasPreviousPage: false,
  startCursor: null,
  endCursor: null,
};

const defaultPresetVersionIds = ['gid://gitlab/Cd::Version/1', 'gid://gitlab/Cd::Version/3'];

const buildVersionSets = (presetVersionIds) =>
  presetVersionIds.length
    ? [
        {
          id: 'gid://gitlab/Cd::VersionSet/1',
          versionSetEntries: {
            nodes: presetVersionIds.map((versionId, index) => ({
              id: `gid://gitlab/Cd::VersionSetEntry/${index + 1}`,
              version: { id: versionId, name: `preset-${index + 1}` },
            })),
          },
        },
      ]
    : [];

export const cdApplicationServicesResponse = (
  services = mockServices,
  { pageInfo = {}, presetVersionIds = defaultPresetVersionIds } = {},
) => ({
  data: {
    organization: {
      id: 'gid://gitlab/Organizations::Organization/1',
      cdApplication: {
        id: cdApplicationId,
        services: {
          nodes: services,
          pageInfo: { ...DEFAULT_PAGE_INFO, ...pageInfo },
        },
        versionSets: {
          nodes: buildVersionSets(presetVersionIds),
        },
      },
    },
  },
});

export const cdVersionCreateResponse = ({
  id = 'gid://gitlab/Cd::Version/99',
  name = '2026-08-summer',
  createdAt = '2026-08-19T00:00:00Z',
  verified = false,
  errors = [],
} = {}) => ({
  data: {
    cdVersionCreate: {
      version: errors.length ? null : { id, name, createdAt, verified, __typename: 'CdVersion' },
      errors,
    },
  },
});
