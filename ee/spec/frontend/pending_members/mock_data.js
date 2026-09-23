export const pendingMembersResponse = {
  data: {
    group: {
      id: 'gid://gitlab/Group/35',
      pendingMembers: {
        nodes: [
          {
            id: 'gid://gitlab/GroupMember/98',
            email: 'pending_1@gmail.com',
            invited: true,
            avatarUrl:
              'https://www.gravatar.com/avatar/f642d140d8eca76c2a0e20cd7827dbe182681638b310e4dcb729640e0281175b?s=80&d=identicon',
            webUrl: 'https://gitlab.com/pending_1',
            approved: true,
            name: 'John Doe',
            __typename: 'PendingGroupMember',
          },
          {
            id: 'gid://gitlab/GroupMember/100',
            email: 'pending_3@gmail.com',
            invited: true,
            avatarUrl:
              'https://www.gravatar.com/avatar/26ff88e0fdba111305d7a8a018ed41554c413a44c8bd4c6666e3e20126bf1f4a?s=80&d=identicon',
            webUrl: 'https://gitlab.com/pending_3',
            approved: false,
            name: 'Admin',
            __typename: 'PendingGroupMember',
          },
          {
            id: 'gid://gitlab/GroupMember/101',
            email: 'pending_4@gmail.com',
            invited: true,
            avatarUrl:
              'https://www.gravatar.com/avatar/26ff88e0fdba111305d7a8a018ed41554c413a44c8bd4c6666e3e20126bf1f4a?s=80&d=identicon',
            webUrl: 'https://gitlab.com/pending_4',
            approved: false,
            name: 'Jane Doe',
            __typename: 'PendingGroupMember',
          },
        ],
        pageInfo: {
          hasNextPage: true,
          hasPreviousPage: false,
          startCursor: 'MTE',
          endCursor: 'MjA',
          __typename: 'PageInfo',
        },
        __typename: 'PendingGroupMemberConnection',
      },
      __typename: 'Group',
    },
  },
};

export const pendingMembersResponseEmpty = {
  data: {
    group: {
      id: 'gid://gitlab/Group/35',
      pendingMembers: {
        nodes: [],
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: 'MTE',
          endCursor: 'MjA',
          __typename: 'PageInfo',
        },
        __typename: 'PendingGroupMemberConnection',
      },
      __typename: 'Group',
    },
  },
};
