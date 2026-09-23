<script>
export default {
  name: 'DuoChatEmptyStateHeader',
};
</script>

<template>
  <div>
    <h2 class="gl-heading-2 gl-mb-0">
      {{ s__('DuoAgenticChat|GitLab Duo Agent Platform') }}
    </h2>
    <p class="gl-text-subtle">
      {{
        s__(
          'DuoAgenticChat|Collaborate with AI agents to accomplish tasks and answer questions, or use a multi-agent flow to solve a complex problem.',
        )
      }}
    </p>
  </div>
</template>
