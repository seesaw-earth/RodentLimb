<script setup lang="ts">
// English / 中文 link in the top bar on every screen size. It opens the same page in the other
// language. (VitePress's own language menu is hidden in custom.css so there is only one switch.)
import { computed } from 'vue'
import { useData, withBase } from 'vitepress'

const { page, localeIndex } = useData()
const isZh = computed(() => localeIndex.value === 'zh')

const href = computed(() => {
  if (page.value.isNotFound) return withBase(isZh.value ? '/' : '/zh/')
  let rel = page.value.relativePath
    .replace(/(^|\/)index\.md$/, '$1')
    .replace(/\.md$/, '.html')
  rel = isZh.value ? rel.replace(/^zh\//, '') : `zh/${rel}`
  return withBase(`/${rel}`)
})
</script>

<template>
  <a
    class="rf-lang-switch"
    :href="href"
    :lang="isZh ? 'en' : 'zh-CN'"
    :hreflang="isZh ? 'en' : 'zh-CN'"
    :title="isZh ? 'English version of this page' : '本页中文版'"
  >{{ isZh ? 'English' : '中文' }}</a>
</template>

<style scoped>
.rf-lang-switch {
  display: flex;
  align-items: center;
  align-self: center;
  margin: 0 4px 0 8px;
  padding: 3px 11px;
  border: 1px solid var(--vp-c-brand-1);
  border-radius: 999px;
  font-size: 13px;
  font-weight: 600;
  line-height: 20px;
  color: var(--vp-c-brand-1);
  white-space: nowrap;
  transition: background-color 0.2s, color 0.2s;
}

.rf-lang-switch:hover {
  background: var(--vp-c-brand-1);
  color: var(--vp-c-white);
}
</style>
