import { createContentLoader } from 'vitepress'

interface BlogPost {
  title: string
  date: string
  displayDate: string
  description: string
  url: string
}

function requiredString(value: unknown, field: string, source: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`Blog post ${source} is missing a ${field} value.`)
  }

  return value
}

export default createContentLoader<BlogPost[]>('blog/*.md', {
  transform(pages) {
    return pages
      .filter(({ frontmatter }) => frontmatter.blog === true)
      .map(({ url, frontmatter }) => {
        const title = requiredString(frontmatter.title, 'title', url)
        const date = requiredString(frontmatter.date, 'date', url)
        const description = requiredString(frontmatter.description, 'description', url)
        const displayDate = new Intl.DateTimeFormat('en', {
          dateStyle: 'long',
          timeZone: 'UTC',
        }).format(new Date(`${date}T00:00:00Z`))

        return { title, date, displayDate, description, url }
      })
      .sort((a, b) => b.date.localeCompare(a.date))
  },
})
