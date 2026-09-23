<script>
import { uniqueId } from 'lodash-es';
import { GlBadge } from '@gitlab/ui';

export default {
  name: 'DashboardHeroHeader',
  components: {
    GlBadge,
  },
  data() {
    return {
      // Unique per instance so SVG defs don't collide when rendered twice.
      areaGradientId: uniqueId('dashboard-hero-area-gradient-'),
      fadeGradientId: uniqueId('dashboard-hero-fade-gradient-'),
      fadeMaskId: uniqueId('dashboard-hero-fade-mask-'),
    };
  },
  solidLinePath: 'M0,116 C60,108 120,98 170,78 C220,58 265,52 312,36 C348,25 378,18 400,14',
  solidAreaPath:
    'M0,116 C60,108 120,98 170,78 C220,58 265,52 312,36 C348,25 378,18 400,14 L400,140 L0,140 Z',
  solidLineDots: [
    { cx: 170, cy: 78 },
    { cx: 312, cy: 36 },
  ],
  dashedLinePath: 'M0,132 C70,126 130,118 185,104 C240,90 300,80 356,66 C380,60 392,57 400,55',
  dashedLineDots: [
    { cx: 185, cy: 104 },
    { cx: 356, cy: 66 },
  ],
};
</script>
<template>
  <header
    class="gl-border-b gl-relative gl-overflow-hidden gl-border-default gl-py-6"
    data-testid="dashboard-hero-header"
  >
    <div
      class="gl-absolute gl-inset-0 gl-bg-gradient-to-r gl-from-purple-50 gl-to-transparent"
      data-testid="dashboard-hero-header-background"
      aria-hidden="true"
    ></div>
    <!-- Decorative rising trend lines; the mask fades them in from the left so
         they blend into the hero background behind the text. -->
    <svg
      class="gl-absolute gl-inset-y-0 gl-right-0 gl-h-full gl-w-1/2 @max-md:gl-hidden"
      viewBox="0 0 400 140"
      preserveAspectRatio="xMaxYMid slice"
      role="presentation"
      focusable="false"
      aria-hidden="true"
      data-testid="dashboard-hero-header-illustration"
    >
      <defs>
        <linearGradient :id="areaGradientId" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="currentColor" stop-opacity="0.3" />
          <stop offset="100%" stop-color="currentColor" stop-opacity="0" />
        </linearGradient>
        <linearGradient :id="fadeGradientId" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stop-color="white" stop-opacity="0" />
          <stop offset="55%" stop-color="white" stop-opacity="0.7" />
          <stop offset="100%" stop-color="white" stop-opacity="1" />
        </linearGradient>
        <mask :id="fadeMaskId">
          <rect width="400" height="140" :fill="`url(#${fadeGradientId})`" />
        </mask>
      </defs>
      <g :mask="`url(#${fadeMaskId})`">
        <g class="gl-text-data-viz-blue-500">
          <path :d="$options.solidAreaPath" :fill="`url(#${areaGradientId})`" stroke="none" />
          <path
            :d="$options.solidLinePath"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
          />
          <circle
            v-for="(dot, index) in $options.solidLineDots"
            :key="index"
            :cx="dot.cx"
            :cy="dot.cy"
            r="4"
            fill="currentColor"
          />
        </g>
        <g class="gl-text-data-viz-orange-500">
          <path
            :d="$options.dashedLinePath"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-dasharray="6 6"
            stroke-linecap="round"
          />
          <circle
            v-for="(dot, index) in $options.dashedLineDots"
            :key="index"
            :cx="dot.cx"
            :cy="dot.cy"
            r="4"
            fill="currentColor"
          />
        </g>
      </g>
    </svg>
    <!-- Only the text keeps the content gutter; the gradient and illustration
         stay full-bleed. -->
    <div class="gl-relative gl-max-w-88 gl-px-5" data-testid="dashboard-hero-header-text">
      <gl-badge icon="tanuki" variant="info">{{
        s__('AnalyticsDashboards|GitLab Analytics')
      }}</gl-badge>
      <h1 class="gl-mb-2 gl-mt-3 gl-text-size-h-display">{{ __('Analytics dashboards') }}</h1>
      <p class="gl-m-0 gl-text-subtle">
        {{ s__('AnalyticsDashboards|Keep your teams aligned around the metrics that matter most') }}
      </p>
    </div>
  </header>
</template>
