import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import HomeHero from './HomeHero.vue'
import QuiperScreenshot from './QuiperScreenshot.vue'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('QuiperScreenshot', QuiperScreenshot)
  },
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'home-hero-image': () => h(HomeHero),
    })
  },
}
