<template>
  <div class="quiper-home-hero">
    <QuiperScreenshot class="quiper-home-hero-image" />
  </div>
</template>

<script setup lang="ts">
import QuiperScreenshot from './QuiperScreenshot.vue'
</script>

<style>
.quiper-home-hero {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
}

.quiper-home-hero-image {
  width: 100%;
  max-width: 720px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 14px;
  overflow: hidden;
  box-shadow: 0 16px 48px rgba(0, 0, 0, 0.18);
}

html.dark .quiper-home-hero-image {
  box-shadow: 0 16px 48px rgba(0, 0, 0, 0.4);
}

</style>
