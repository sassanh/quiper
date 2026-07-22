---
title: Quiper Blog
description: Engineering notes about building Quiper, a native AI overlay for macOS.
image: /blog/quiper-overlay.webp
blogIndex: true
sidebar: false
aside: false
editLink: false
lastUpdated: false
prev: false
next: false
---

<script setup lang="ts">
import { withBase } from 'vitepress'
import { data as posts } from './posts.data'
</script>

# Quiper Blog

Engineering notes about building a fast, native way to work with AI on macOS.

<div class="blog-posts">
  <article v-for="post in posts" :key="post.url" class="blog-post">
    <time :datetime="post.date">{{ post.displayDate }}</time>
    <h2><a :href="withBase(post.url)">{{ post.title }}</a></h2>
    <p>{{ post.description }}</p>
    <a :href="withBase(post.url)" :aria-label="`Read ${post.title}`">Read article →</a>
  </article>
</div>

<style scoped>
.blog-posts {
  margin-top: 2.5rem;
}

.blog-post {
  padding: 1.75rem 0;
  border-top: 1px solid var(--vp-c-divider);
}

.blog-post:last-child {
  border-bottom: 1px solid var(--vp-c-divider);
}

.blog-post time {
  color: var(--vp-c-text-2);
  font-size: 0.875rem;
}

.blog-post h2 {
  margin: 0.35rem 0 0.5rem;
  border: 0;
}

.blog-post h2 a {
  color: var(--vp-c-text-1);
  text-decoration: none;
}

.blog-post h2 a:hover {
  color: var(--vp-c-brand-1);
}

.blog-post p {
  margin: 0 0 0.75rem;
  color: var(--vp-c-text-2);
}
</style>
