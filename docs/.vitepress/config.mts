import { defineConfig, type DefaultTheme } from 'vitepress'

// Published at https://seesaw-earth.github.io/RodentLimb/ — every absolute link below is
// relative to this base. Change `base` if the repository is renamed.
const base = '/RodentLimb/'
const repo = 'https://github.com/seesaw-earth/RodentLimb'

function sidebarEn(): DefaultTheme.Sidebar {
  return [
    {
      text: 'Getting started',
      items: [
        { text: 'What is RodentLimb?', link: '/guide/introduction' },
        { text: 'Quick start', link: '/guide/getting-started' },
        { text: 'Recording videos that track well', link: '/guide/recording' }
      ]
    },
    {
      text: 'Using the app',
      items: [
        { text: 'Calibration', link: '/guide/calibration' },
        { text: 'Results & review', link: '/guide/results' },
        { text: 'Parameters', link: '/guide/parameters' },
        { text: 'Data, groups & export', link: '/guide/data' }
      ]
    },
    {
      text: 'Assays',
      items: [
        { text: 'Overview', link: '/assays/' },
        { text: 'Tail suspension', link: '/assays/tail-suspension' },
        { text: 'Cylinder test', link: '/assays/cylinder' },
        { text: 'Gait analysis', link: '/assays/gait' }
      ]
    },
    {
      text: 'How it works',
      items: [
        { text: 'Pose model & cleaning', link: '/principles/pose' },
        { text: 'Validation', link: '/principles/validation' }
      ]
    },
    {
      text: 'Reference',
      items: [
        { text: 'Files & exports', link: '/reference/files' },
        { text: 'FAQ & troubleshooting', link: '/reference/faq' },
        { text: 'References', link: '/reference/reading' },
        { text: 'Release notes', link: '/reference/changelog' }
      ]
    },
    {
      text: 'About',
      items: [
        { text: 'Open source & building', link: '/source' },
        { text: 'Privacy policy', link: '/privacy' },
        { text: 'Support', link: '/support' }
      ]
    }
  ]
}

function sidebarZh(): DefaultTheme.Sidebar {
  return [
    {
      text: '入门',
      items: [
        { text: 'RodentLimb 是什么', link: '/zh/guide/introduction' },
        { text: '快速上手', link: '/zh/guide/getting-started' },
        { text: '怎样拍出好识别的视频', link: '/zh/guide/recording' }
      ]
    },
    {
      text: '使用 App',
      items: [
        { text: '标定', link: '/zh/guide/calibration' },
        { text: '结果与回放', link: '/zh/guide/results' },
        { text: '参数', link: '/zh/guide/parameters' },
        { text: '数据、组间比较与导出', link: '/zh/guide/data' }
      ]
    },
    {
      text: '实验范式',
      items: [
        { text: '总览', link: '/zh/assays/' },
        { text: '悬尾实验', link: '/zh/assays/tail-suspension' },
        { text: '圆筒实验', link: '/zh/assays/cylinder' },
        { text: '步态分析', link: '/zh/assays/gait' }
      ]
    },
    {
      text: '原理',
      items: [
        { text: '姿态模型与预处理', link: '/zh/principles/pose' },
        { text: '验证', link: '/zh/principles/validation' }
      ]
    },
    {
      text: '参考',
      items: [
        { text: '文件与导出', link: '/zh/reference/files' },
        { text: '常见问题与排错', link: '/zh/reference/faq' },
        { text: '参考文献', link: '/zh/reference/reading' },
        { text: '版本说明', link: '/zh/reference/changelog' }
      ]
    },
    {
      text: '关于',
      items: [
        { text: '开源与构建', link: '/zh/source' },
        { text: '隐私政策', link: '/zh/privacy' },
        { text: '支持', link: '/zh/support' }
      ]
    }
  ]
}

export default defineConfig({
  base,
  title: 'RodentLimb',
  description: 'Limb-pose analysis of tail suspension, cylinder and gait tests on iPhone — user manual',
  lastUpdated: false,
  cleanUrls: false,
  head: [
    ['link', { rel: 'icon', type: 'image/png', href: `${base}favicon-64.png` }],
    ['link', { rel: 'apple-touch-icon', href: `${base}apple-touch-icon.png` }],
    ['meta', { name: 'theme-color', content: '#2f7bf5' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: 'RodentLimb — user manual' }],
    ['meta', { property: 'og:image', content: `https://seesaw-earth.github.io${base}hero.png` }]
  ],
  markdown: {
    image: { lazyLoading: true }
  },
  themeConfig: {
    logo: '/logo.png',
    socialLinks: [{ icon: 'github', link: repo }],
    search: {
      provider: 'local',
      options: {
        locales: {
          zh: {
            translations: {
              button: { buttonText: '搜索', buttonAriaLabel: '搜索' },
              modal: {
                displayDetails: '显示详细列表',
                resetButtonTitle: '清除',
                backButtonTitle: '关闭搜索',
                noResultsText: '没有找到',
                footer: { selectText: '选择', navigateText: '切换', closeText: '关闭' }
              }
            }
          }
        }
      }
    }
  },
  locales: {
    root: {
      label: 'English',
      lang: 'en-US',
      title: 'RodentLimb',
      description: 'Limb-pose analysis of tail suspension, cylinder and gait tests on iPhone — user manual',
      themeConfig: {
        nav: [
          { text: 'Guide', link: '/guide/introduction', activeMatch: '/guide/' },
          { text: 'Assays', link: '/assays/', activeMatch: '/assays/' },
          { text: 'How it works', link: '/principles/pose', activeMatch: '/principles/' },
          { text: 'Reference', link: '/reference/files', activeMatch: '/reference/' },
          { text: 'Source code', link: '/source' },
          { text: 'Support', link: '/support' }
        ],
        sidebar: sidebarEn(),
        outline: { level: [2, 3], label: 'On this page' },
        docFooter: { prev: 'Previous', next: 'Next' },
        editLink: { pattern: `${repo}/edit/main/docs/:path`, text: 'Edit this page on GitHub' },
        footer: {
          message: `RodentLimb · open source under the GNU AGPL-3.0 · <a href="${repo}">Source on GitHub</a> · <a href="${base}privacy.html">Privacy</a> · <a href="${base}support.html">Support</a>`,
          copyright: '© 2026 Ziqing Shi'
        }
      }
    },
    zh: {
      label: '简体中文',
      lang: 'zh-CN',
      link: '/zh/',
      title: 'RodentLimb',
      description: '在 iPhone 上完成悬尾、圆筒与步态实验的肢体姿态分析 —— 使用手册',
      themeConfig: {
        nav: [
          { text: '指南', link: '/zh/guide/introduction', activeMatch: '/zh/guide/' },
          { text: '实验范式', link: '/zh/assays/', activeMatch: '/zh/assays/' },
          { text: '原理', link: '/zh/principles/pose', activeMatch: '/zh/principles/' },
          { text: '参考', link: '/zh/reference/files', activeMatch: '/zh/reference/' },
          { text: '源代码', link: '/zh/source' },
          { text: '支持', link: '/zh/support' }
        ],
        sidebar: sidebarZh(),
        outline: { level: [2, 3], label: '本页目录' },
        docFooter: { prev: '上一页', next: '下一页' },
        editLink: { pattern: `${repo}/edit/main/docs/:path`, text: '在 GitHub 上编辑此页' },
        langMenuLabel: '切换语言',
        returnToTopLabel: '回到顶部',
        sidebarMenuLabel: '目录',
        darkModeSwitchLabel: '外观',
        lightModeSwitchTitle: '切换到浅色模式',
        darkModeSwitchTitle: '切换到深色模式',
        skipToContentLabel: '跳到正文',
        notFound: {
          title: '页面不存在',
          quote: '这个地址没有内容，可能已经移动。',
          linkLabel: '回到首页',
          linkText: '回到首页'
        },
        footer: {
          message: `RodentLimb · GNU AGPL-3.0 开源 · <a href="${repo}">GitHub 源代码</a> · <a href="${base}zh/privacy.html">隐私政策</a> · <a href="${base}zh/support.html">支持</a>`,
          copyright: '© 2026 Ziqing Shi'
        }
      }
    }
  }
})
