export const mockCreditCapsData = {
  data: {
    subscriptionUsage: {
      budgetCaps: {
        flatUserCap: 500,
        flatUserCapEnabled: true,
      },
    },
  },
};

export const mockCreditCapsDataDisabled = {
  data: {
    subscriptionUsage: {
      budgetCaps: {
        flatUserCap: 500,
        flatUserCapEnabled: false,
      },
    },
  },
};

export const mockCreditCapsNullCap = {
  data: {
    subscriptionUsage: {
      budgetCaps: {
        flatUserCap: null,
        flatUserCapEnabled: null,
      },
    },
  },
};

export const mockCreditCapsDataZeroCap = {
  data: {
    subscriptionUsage: {
      budgetCaps: {
        flatUserCap: 0,
        flatUserCapEnabled: true,
      },
    },
  },
};

export const mockCreditCapsBudgetCapsNull = {
  data: {
    subscriptionUsage: {
      budgetCaps: null,
    },
  },
};

export const mockUpsertFlatUserCapSuccess = {
  data: {
    upsertFlatUserCap: {
      flatUserCap: 300,
      flatUserCapEnabled: false,
      errors: [],
    },
  },
};

export const mockUpsertFlatUserCapErrors = {
  data: {
    upsertFlatUserCap: {
      flatUserCap: null,
      flatUserCapEnabled: null,
      errors: ['Something went wrong'],
    },
  },
};

export const mockUpsertFlatUserCapMultipleErrors = {
  data: {
    upsertFlatUserCap: {
      flatUserCap: null,
      flatUserCapEnabled: null,
      errors: ['First error', 'Second error'],
    },
  },
};

export const mockUserOverride = {
  cap: 20,
  capEnabled: true,
  user: {
    id: 'gid://gitlab/User/1',
    name: 'Alice Smith',
    username: 'alice.smith',
    avatarUrl: 'https://www.gravatar.com/avatar/a1b2c3d4e5f6?s=80&d=identicon',
    webPath: '/alice.smith',
  },
};

const mockUserOverrideDisabled = {
  cap: 8,
  capEnabled: false,
  user: {
    id: 'gid://gitlab/User/2',
    name: 'Bob Jones',
    username: 'bob.jones',
    avatarUrl: 'https://www.gravatar.com/avatar/b2c3d4e5f6a1?s=80&d=identicon',
    webPath: '/bob.jones',
  },
};

const mockUserOverrides20 = [
  {
    cap: 20,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/1',
      name: 'Alice Smith',
      username: 'alice.smith',
      avatarUrl: 'https://www.gravatar.com/avatar/a1b2c3d4e5f6?s=80&d=identicon',
      webPath: '/alice.smith',
    },
  },
  {
    cap: 8,
    capEnabled: false,
    user: {
      id: 'gid://gitlab/User/2',
      name: 'Bob Jones',
      username: 'bob.jones',
      avatarUrl: 'https://www.gravatar.com/avatar/b2c3d4e5f6a1?s=80&d=identicon',
      webPath: '/bob.jones',
    },
  },
  {
    cap: 15,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/3',
      name: 'Carol White',
      username: 'carol.white',
      avatarUrl: 'https://www.gravatar.com/avatar/c3d4e5f6a1b2?s=80&d=identicon',
      webPath: '/carol.white',
    },
  },
  {
    cap: 5,
    capEnabled: false,
    user: {
      id: 'gid://gitlab/User/4',
      name: 'David Brown',
      username: 'david.brown',
      avatarUrl: 'https://www.gravatar.com/avatar/d4e5f6a1b2c3?s=80&d=identicon',
      webPath: '/david.brown',
    },
  },
  {
    cap: 22,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/5',
      name: 'Eva Martinez',
      username: 'eva.martinez',
      avatarUrl: 'https://www.gravatar.com/avatar/e5f6a1b2c3d4?s=80&d=identicon',
      webPath: '/eva.martinez',
    },
  },
  {
    cap: 10,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/6',
      name: 'Frank Lee',
      username: 'frank.lee',
      avatarUrl: 'https://www.gravatar.com/avatar/f6a1b2c3d4e5?s=80&d=identicon',
      webPath: '/frank.lee',
    },
  },
  {
    cap: 3,
    capEnabled: false,
    user: {
      id: 'gid://gitlab/User/7',
      name: 'Grace Kim',
      username: 'grace.kim',
      avatarUrl: 'https://www.gravatar.com/avatar/a1b2c3d4e5f7?s=80&d=identicon',
      webPath: '/grace.kim',
    },
  },
  {
    cap: 18,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/8',
      name: 'Henry Chen',
      username: 'henry.chen',
      avatarUrl: 'https://www.gravatar.com/avatar/b2c3d4e5f6a8?s=80&d=identicon',
      webPath: '/henry.chen',
    },
  },
  {
    cap: 12,
    capEnabled: false,
    user: {
      id: 'gid://gitlab/User/9',
      name: 'Irene Patel',
      username: 'irene.patel',
      avatarUrl: 'https://www.gravatar.com/avatar/c3d4e5f6a1b9?s=80&d=identicon',
      webPath: '/irene.patel',
    },
  },
  {
    cap: 7,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/10',
      name: 'James Wilson',
      username: 'james.wilson',
      avatarUrl: 'https://www.gravatar.com/avatar/d4e5f6a1b2ca?s=80&d=identicon',
      webPath: '/james.wilson',
    },
  },
  {
    cap: 23,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/11',
      name: 'Karen Davis',
      username: 'karen.davis',
      avatarUrl: 'https://www.gravatar.com/avatar/e5f6a1b2c3db?s=80&d=identicon',
      webPath: '/karen.davis',
    },
  },
  {
    cap: 4,
    capEnabled: false,
    user: {
      id: 'gid://gitlab/User/12',
      name: 'Liam Taylor',
      username: 'liam.taylor',
      avatarUrl: 'https://www.gravatar.com/avatar/f6a1b2c3d4ec?s=80&d=identicon',
      webPath: '/liam.taylor',
    },
  },
  {
    cap: 16,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/13',
      name: 'Mia Anderson',
      username: 'mia.anderson',
      avatarUrl: 'https://www.gravatar.com/avatar/a1b2c3d4e5fd?s=80&d=identicon',
      webPath: '/mia.anderson',
    },
  },
  {
    cap: 9,
    capEnabled: false,
    user: {
      id: 'gid://gitlab/User/14',
      name: 'Noah Thomas',
      username: 'noah.thomas',
      avatarUrl: 'https://www.gravatar.com/avatar/b2c3d4e5f6ae?s=80&d=identicon',
      webPath: '/noah.thomas',
    },
  },
  {
    cap: 21,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/15',
      name: 'Olivia Jackson',
      username: 'olivia.jackson',
      avatarUrl: 'https://www.gravatar.com/avatar/c3d4e5f6a1bf?s=80&d=identicon',
      webPath: '/olivia.jackson',
    },
  },
  {
    cap: 6,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/16',
      name: 'Paul Harris',
      username: 'paul.harris',
      avatarUrl: 'https://www.gravatar.com/avatar/d4e5f6a1b2c0?s=80&d=identicon',
      webPath: '/paul.harris',
    },
  },
  {
    cap: 14,
    capEnabled: false,
    user: {
      id: 'gid://gitlab/User/17',
      name: 'Quinn Martin',
      username: 'quinn.martin',
      avatarUrl: 'https://www.gravatar.com/avatar/e5f6a1b2c3d1?s=80&d=identicon',
      webPath: '/quinn.martin',
    },
  },
  {
    cap: 11,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/18',
      name: 'Rachel Garcia',
      username: 'rachel.garcia',
      avatarUrl: 'https://www.gravatar.com/avatar/f6a1b2c3d4e2?s=80&d=identicon',
      webPath: '/rachel.garcia',
    },
  },
  {
    cap: 2,
    capEnabled: false,
    user: {
      id: 'gid://gitlab/User/19',
      name: 'Samuel Robinson',
      username: 'samuel.robinson',
      avatarUrl: 'https://www.gravatar.com/avatar/a1b2c3d4e5f3?s=80&d=identicon',
      webPath: '/samuel.robinson',
    },
  },
  {
    cap: 19,
    capEnabled: true,
    user: {
      id: 'gid://gitlab/User/20',
      name: 'Tara Lewis',
      username: 'tara.lewis',
      avatarUrl: 'https://www.gravatar.com/avatar/b2c3d4e5f6a4?s=80&d=identicon',
      webPath: '/tara.lewis',
    },
  },
];

const buildUserOverridesResponse = ({
  nodes,
  hasNextPage = false,
  hasPreviousPage = false,
  startCursor = null,
  endCursor = null,
} = {}) => ({
  data: {
    subscriptionUsage: {
      budgetCaps: {
        userOverrides: {
          __typename: 'GitlabSubscriptionBudgetCapUserOverrideConnection',
          nodes,
          pageInfo: {
            __typename: 'PageInfo',
            hasNextPage,
            hasPreviousPage,
            startCursor,
            endCursor,
          },
        },
      },
    },
  },
});

export const mockUserOverridesData = buildUserOverridesResponse({
  nodes: [mockUserOverride, mockUserOverrideDisabled],
});

export const mockUserOverridesEmpty = buildUserOverridesResponse({ nodes: [] });

export const mockUserOverridesWithNullUser = buildUserOverridesResponse({
  nodes: [mockUserOverride, { cap: 5, capEnabled: true, user: null }],
});

export const mockUserOverridesNullBudgetCaps = {
  data: {
    subscriptionUsage: {
      budgetCaps: null,
    },
  },
};

export const mockUserOverridesPage1of2 = buildUserOverridesResponse({
  nodes: mockUserOverrides20.slice(0, 10),
  hasNextPage: true,
  endCursor: 'cursor-page-1',
});

export const mockUserOverridesPage2of2 = buildUserOverridesResponse({
  nodes: mockUserOverrides20.slice(10),
  hasNextPage: false,
  hasPreviousPage: true,
  startCursor: 'cursor-page-1',
  endCursor: null,
});

export const mockUpsertUserOverridesSuccess = {
  data: {
    upsertUserBudgetCapOverrides: {
      userOverrides: [
        {
          cap: mockUserOverride.cap,
          capEnabled: mockUserOverride.capEnabled,
          user: { id: mockUserOverride.user.id },
        },
      ],
      errors: [],
    },
  },
};

export const mockUpsertUserOverridesErrors = {
  data: {
    upsertUserBudgetCapOverrides: {
      userOverrides: null,
      errors: ['Something went wrong'],
    },
  },
};

export const mockUpsertUserOverridesMultipleErrors = {
  data: {
    upsertUserBudgetCapOverrides: {
      userOverrides: null,
      errors: ['First error', 'Second error'],
    },
  },
};

export const mockSearchUsers = [
  {
    __typename: 'User',
    id: 'gid://gitlab/User/101',
    name: 'Diana Prince',
    username: 'diana.prince',
    avatarUrl: 'https://www.gravatar.com/avatar/aa1?s=80&d=identicon',
    webUrl: 'https://gitlab.com/diana.prince',
    webPath: '/diana.prince',
  },
  {
    __typename: 'User',
    id: 'gid://gitlab/User/102',
    name: 'Clark Kent',
    username: 'clark.kent',
    avatarUrl: 'https://www.gravatar.com/avatar/aa2?s=80&d=identicon',
    webUrl: 'https://gitlab.com/clark.kent',
    webPath: '/clark.kent',
  },
];

export const mockSearchAllUsersResult = {
  data: {
    users: {
      __typename: 'UserConnection',
      nodes: mockSearchUsers,
    },
  },
};

export const mockSearchGroupUsersResult = {
  data: {
    namespace: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      users: {
        __typename: 'GroupMemberConnection',
        nodes: mockSearchUsers.map((user) => ({
          __typename: 'GroupMember',
          id: `member-${user.id}`,
          user,
        })),
        pageInfo: {
          __typename: 'PageInfo',
          hasNextPage: false,
          endCursor: null,
          startCursor: null,
        },
      },
    },
  },
};
