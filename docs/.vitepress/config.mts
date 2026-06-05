import { defineConfig } from 'vitepress'

export default defineConfig({
  base: '/quiper/',
  title: 'Quiper',
  description: 'Unified AI overlay for macOS — documentation and guides.',

  head: [
    ['meta', { name: 'theme-color', content: '#7c3aed' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: 'Quiper Documentation' }],
    [
      'meta',
      {
        property: 'og:description',
        content:
          'Comprehensive guides for Quiper — the instant-access AI overlay for macOS.',
      },
    ],
  ],

  themeConfig: {
    logo: '/logo.png',

    nav: [
      { text: 'Guide', link: '/getting-started' },
      { text: 'GitHub', link: 'https://github.com/sassanh/quiper' },
    ],

    sidebar: [
      {
        text: 'Introduction',
        items: [
          { text: 'Overview', link: '/' },
          { text: 'Getting Started', link: '/getting-started' },
        ],
      },
      {
        text: 'Usage',
        items: [
          { text: 'Daily Workflow & Shortcuts', link: '/daily-workflow' },
          { text: 'Managing Engines', link: '/engines' },
          { text: 'Application Settings', link: '/settings' },
        ],
      },
      {
        text: 'Customization',
        items: [
          { text: 'Appearance Settings', link: '/appearance' },
          { text: 'Custom Actions (JS)', link: '/custom-actions' },
        ],
      },
      {
        text: 'Advanced',
        items: [
          { text: 'Touch ID & Security', link: '/security' },
          { text: 'Troubleshooting', link: '/troubleshooting' },
        ],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/sassanh/quiper' },
    ],

    search: {
      provider: 'local',
    },

    editLink: {
      pattern: 'https://github.com/sassanh/quiper/edit/main/docs/:path',
      text: 'Edit this page on GitHub',
    },

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2024-present Sassan Haradji',
    },
  },
})
