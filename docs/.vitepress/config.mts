import { defineConfig } from 'vitepress'

const siteUrl = 'https://quiper.sassanh.com'
const siteBase = '/'

function pageUrl(relativePath: string): string {
  const route = relativePath
    .replace(/(^|\/)index\.md$/, '$1')
    .replace(/\.md$/, '')

  return new URL(`${siteBase}${route}`, siteUrl).href
}

export default defineConfig({
  base: siteBase,
  cleanUrls: true,
  title: 'Quiper',
  description: 'Unified AI overlay for macOS — documentation and guides.',

  sitemap: {
    hostname: siteUrl,
    transformItems: (items) => items.filter((item) => !item.url.includes('TODO')),
  },

  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: `${siteBase}favicon.svg` }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '32x32', href: `${siteBase}favicon-32x32.png`, media: '(prefers-color-scheme: light)' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '32x32', href: `${siteBase}favicon-32x32-dark.png`, media: '(prefers-color-scheme: dark)' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '16x16', href: `${siteBase}favicon-16x16.png`, media: '(prefers-color-scheme: light)' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '16x16', href: `${siteBase}favicon-16x16-dark.png`, media: '(prefers-color-scheme: dark)' }],
    ['link', { rel: 'icon', type: 'image/x-icon', href: `${siteBase}favicon.ico` }],
    ['link', { rel: 'apple-touch-icon', sizes: '180x180', href: `${siteBase}apple-touch-icon.png` }],
    ['meta', { name: 'theme-color', content: '#7c3aed' }],
    ['script', {}, `if (location.hostname === 'sassanh.github.io') { location.replace('https://quiper.sassanh.com' + location.pathname.replace(/^\\/quiper\\/?/, '/') + location.search + location.hash); }`],
  ],

  transformHead({ pageData }) {
    if (pageData.relativePath === 'engines-setup/TODO.md') {
      return [['meta', { name: 'robots', content: 'noindex' }]]
    }

    const isBlogPost = pageData.frontmatter.blog === true
    const isBlogIndex = pageData.frontmatter.blogIndex === true

    if (!isBlogPost && !isBlogIndex) {
      return
    }

    const canonicalUrl = pageUrl(pageData.relativePath)
    const imagePath = typeof pageData.frontmatter.image === 'string'
      ? pageData.frontmatter.image
      : '/og-image.png'
    const imageUrl = new URL(`${siteBase}${imagePath.replace(/^\//, '')}`, siteUrl).href

    const head = [
      ['link', { rel: 'canonical', href: canonicalUrl }],
      ['meta', { property: 'og:type', content: isBlogPost ? 'article' : 'website' }],
      ['meta', { property: 'og:site_name', content: 'Quiper' }],
      ['meta', { property: 'og:title', content: pageData.title }],
      ['meta', { property: 'og:description', content: pageData.description }],
      ['meta', { property: 'og:url', content: canonicalUrl }],
      ['meta', { property: 'og:image', content: imageUrl }],
      ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
      ['meta', { name: 'twitter:title', content: pageData.title }],
      ['meta', { name: 'twitter:description', content: pageData.description }],
      ['meta', { name: 'twitter:image', content: imageUrl }],
    ]

    if (isBlogPost) {
      head.push([
        'meta',
        { property: 'article:published_time', content: pageData.frontmatter.date },
      ])
    }

    return head
  },

  themeConfig: {
    logo: { light: '/logo-light.png', dark: '/logo-dark.png' },

    nav: [
      { text: 'Guide', link: '/getting-started' },
      { text: 'Blog', link: '/blog/' },
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
          { text: 'Setting Up Engines', link: '/engines-setup', items: [
            { text: 'Gemini', link: '/engines-setup/gemini' },
            { text: 'Grok', link: '/engines-setup/grok' },
          ] },
          { text: 'Managing Engines', link: '/engines' },
          { text: 'Application Settings', link: '/settings' },
          { text: 'Tab History Switcher', link: '/tab-history' },
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
      {
        text: 'Contributing',
        items: [
          { text: 'Settings Styling Standards', link: '/settings-styling' },
          { text: 'Default Template Validation', link: '/default-template-validation' },
          { text: 'Version Ordering', link: '/version-ordering' },
          { text: 'Migration Architecture', link: '/migrations' },
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
