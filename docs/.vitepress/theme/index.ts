import { h } from 'vue'
import DefaultTheme from 'vitepress/theme'
import type { Theme } from 'vitepress'
import LangSwitch from './LangSwitch.vue'
import './custom.css'

export default {
  extends: DefaultTheme,
  // Visible English / 中文 switch in the top bar on every page (see LangSwitch.vue).
  Layout: () => h(DefaultTheme.Layout, null, { 'nav-bar-content-after': () => h(LangSwitch) })
} satisfies Theme
