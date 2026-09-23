import { uniqueId } from 'lodash-es';
import { slugify } from '~/lib/utils/text_utility';

const DEFAULT_EVENT = {
  action: 'Signed in with STANDARD authentication',
  date: '2020-03-18 12:04:23',
  ip_address: '127.0.0.1',
};

const populateEvent = (user, hasAuthorUrl = true, hasObjectUrl = true) => {
  const author = { name: user, url: null };
  const object = { name: user, url: null };
  const userSlug = slugify(user);

  if (hasAuthorUrl) {
    author.url = `/${userSlug}`;
  }

  if (hasObjectUrl) {
    object.url = `http://127.0.0.1:3000/${userSlug}`;
  }

  return {
    ...DEFAULT_EVENT,
    author,
    object,
    target: user,
  };
};

export const verification = [
  'id5hzCbERzSkQ82tAs16tH5Y',
  'JsSQtg86au6buRtX9j98sYa8',
  'Cr28SHnrJtgpSXUEGfictGMS',
];

export default () => [
  populateEvent('User'),
  populateEvent('User 2', false),
  populateEvent('User 3', true, false),
  populateEvent('User 4', false, false),
];

const mockExternalDestinationUrl = 'https://api.gitlab.com';
const mockExternalDestinationName = 'Name';
export const mockExternalDestinationHeader = () => ({
  id: uniqueId('gid://gitlab/AuditEvents::Streaming::Header/'),
  key: uniqueId('header-key-'),
  value: uniqueId('header-value-'),
  active: false,
});

const makeHeader = () => ({
  __typename: 'AuditEventStreamingHeader',
  id: `header-id-${uniqueId()}`,
  key: `header-key-${uniqueId()}`,
  value: 'header-value',
  active: false,
});

const makeNamespaceFilter = () => ({
  __typename: 'AuditEventStreamingHTTPNamespaceFilter',
  id: uniqueId('gid://gitlab/AuditEvents::Streaming::HTTP::NamespaceFilter/'),
  namespace: {
    id: `namespace-id-${uniqueId()}`,
    name: `namespace name`,
    fullName: `namespace full name`,
    fullPath: `namespace-full-path`,
    __typename: `Namespace`,
  },
});

export const newStreamDestination = {
  name: '',
  config: {},
  category: 'http',
  namespaceFilters: [],
  eventTypeFilters: [],
};

export const mockExternalDestinations = [
  {
    __typename: 'ExternalAuditEventDestination',
    id: 'test_id1',
    name: mockExternalDestinationName,
    destinationUrl: mockExternalDestinationUrl,
    verificationToken: verification[0],
    headers: {
      nodes: [],
    },
    eventTypeFilters: [],
    namespaceFilter: null,
    active: true,
  },
  {
    __typename: 'ExternalAuditEventDestination',
    id: 'test_id2',
    name: mockExternalDestinationName,
    destinationUrl: 'https://apiv2.gitlab.com',
    verificationToken: verification[1],
    eventTypeFilters: ['add_gpg_key', 'user_created'],
    headers: {
      nodes: [makeHeader(), makeHeader()],
    },
    namespaceFilter: makeNamespaceFilter(),
    active: true,
  },
];

export const groupPath = 'test-group';

export const instanceGroupPath = 'instance';

const testGroupId = 'test-group-id';

export const destinationCreateMutationPopulator = (errors = []) => {
  const correctData = {
    errors,
    externalAuditEventDestination: {
      __typename: 'ExternalAuditEventDestination',
      id: 'test-create-id',
      name: mockExternalDestinationName,
      destinationUrl: mockExternalDestinationUrl,
      verificationToken: verification[2],
      group: {
        name: groupPath,
        id: testGroupId,
      },
      eventTypeFilters: null,
      headers: {
        nodes: [],
      },
      namespaceFilter: null,
      active: true,
    },
  };

  const errorData = {
    errors,
    googleCloudLoggingConfiguration: null,
  };

  return {
    data: {
      externalAuditEventDestinationCreate: errors.length > 0 ? errorData : correctData,
    },
  };
};

export const destinationDeleteMutationPopulator = (errors = []) => ({
  data: {
    externalAuditEventDestinationDestroy: {
      errors,
    },
  },
});

export const mockSvgPath = 'mock/path';

export const mockAuditEventDefinitions = [
  {
    event_name: 'add_gpg_key',
    feature_category: 'compliance_management',
  },
  {
    event_name: 'user_created',
    feature_category: 'user_management',
  },
  {
    event_name: 'user_blocked',
    feature_category: 'user_management',
  },
  {
    event_name: 'project_unarchived',
    feature_category: 'compliance_management',
  },
];
export const getMockNamespaceFilters = () => ({
  data: {
    group: {
      id: 'gid://gitlab/Group/1',
      projects: {
        nodes: [
          {
            id: 'gid://gitlab/Project/1',
            name: 'project 1',
            fullPath: 'gitlab-org/project-1',
            __typename: 'Project',
          },
          {
            id: 'gid://gitlab/Project/2',
            name: 'project 2',
            fullPath: 'gitlab-org/project-2',
            __typename: 'Project',
          },
        ],
        __typename: 'ProjectConnection',
      },
      descendantGroups: {
        nodes: [
          {
            id: 'gid://gitlab/Group/104',
            name: 'group-sub-1',
            fullPath: 'gitlab-org/group-sub-1',
            __typename: 'Group',
          },
          {
            id: 'gid://gitlab/Group/111',
            name: 'group-sub-2',
            fullPath: 'gitlab-org/group-sub-2',
            __typename: 'Group',
          },
        ],
        __typename: 'GroupConnection',
      },
      __typename: 'Group',
    },
  },
});
