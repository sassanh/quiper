<template>
  <div class="quiper-theme-screenshot" role="img" :aria-label="label">
    <img
      :src="heroLight"
      alt=""
      class="light-only"
      width="1728"
      height="952"
    >
    <img
      :src="heroDark"
      alt=""
      class="dark-only"
      width="1728"
      height="952"
    >
  </div>
</template>

<script setup lang="ts">
import heroDark from '../../../.github/assets/hero.webp'
import heroLight from '../../../.github/assets/hero-light.webp'

withDefaults(defineProps<{
  label?: string
}>(), {
  label: 'Quiper showing a local AI coding session over Xcode',
})
</script>

<style>
.quiper-theme-screenshot img {
  display: block;
  width: 100%;
  height: auto;
}

html.dark .quiper-theme-screenshot .light-only,
html:not(.dark) .quiper-theme-screenshot .dark-only {
  display: none;
}
</style>
