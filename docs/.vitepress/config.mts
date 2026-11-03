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
        { text: 'Quick start on Mac', link: '/guide/getting-started' },
        { text: 'Recording videos', link: '/guide/recording' },
        { text: 'iPhone & iPad', link: '/guide/iphone' }
      ]
    },
    {
      text: 'Using the Mac app',
      items: [
        { text: 'Importing videos', link: '/guide/import' },
        { text: 'Processing queue', link: '/guide/processing' },
        { text: 'Quality control & inclusion', link: '/guide/qc' },
        { text: 'Tasks, parameters & presets', link: '/guide/parameters' },
        { text: 'Calibration', link: '/guide/calibration' },
        { text: 'Results & review', link: '/guide/results' },
        { text: 'Studies, groups & blinding', link: '/guide/data' },
        { text: 'Export', link: '/guide/export' },
        { text: 'Keyboard shortcuts', link: '/guide/shortcuts' }
      ]
    },
    {
      text: 'Tasks',
      items: [
        { text: 'Overview', link: '/assays/' },
        { text: 'Tail suspension', link: '/assays/tail-suspension' },
        { text: 'Cylinder test', link: '/assays/cylinder' },
        { text: 'Gait analysis', link: '/assays/gait' },
        { text: 'Itch (scratching)', link: '/assays/itch' },
        { text: 'Spontaneous pain', link: '/assays/pain' },
        { text: 'Self-grooming', link: '/assays/grooming' },
        { text: 'Seizure scoring', link: '/assays/seizure' }
      ]
    },
    {
      text: 'How it works',
      items: [
        { text: 'Pose estimation & cleaning', link: '/principles/pose' },
        { text: 'Validation & limits', link: '/principles/validation' }
      ]
    },
    {
      text: 'Pose models',
      items: [
        { text: 'Models & provenance', link: '/models/' },
        { text: 'CylinderPose7 (visible light)', link: '/models/cylinderpose7' },
        { text: 'PalmReaderPose8 (near-infrared)', link: '/models/palmreader8' },
        { text: 'How to cite', link: '/models/cite' }
      ]
    },
    {
      text: 'Reference',
      items: [
        { text: 'Library & files', link: '/reference/files' },
        { text: 'FAQ & troubleshooting', link: '/reference/faq' },
        { text: 'References', link: '/reference/reading' },
        { text: 'Release notes', link: '/reference/changelog' }
      ]
    },
    {
      text: 'About',
      items: [
        { text: 'Source code', link: '/source' },
        { text: 'Privacy policy', link: '/privacy' },
        { text: 'Support', link: '/support' },
        { text: 'Legal & notices', link: '/legal' },
        { text: 'Accessibility', link: '/accessibility' }
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
        { text: 'Mac 快速上手', link: '/zh/guide/getting-started' },
        { text: '视频拍摄', link: '/zh/guide/recording' },
        { text: 'iPhone 与 iPad', link: '/zh/guide/iphone' }
      ]
    },
    {
      text: '使用 Mac 版',
      items: [
        { text: '导入视频', link: '/zh/guide/import' },
        { text: '处理队列', link: '/zh/guide/processing' },
        { text: '质量控制与纳入', link: '/zh/guide/qc' },
        { text: '任务、参数与预设', link: '/zh/guide/parameters' },
        { text: '标定', link: '/zh/guide/calibration' },
        { text: '结果与复核', link: '/zh/guide/results' },
        { text: '研究、分组与盲法', link: '/zh/guide/data' },
        { text: '导出', link: '/zh/guide/export' },
        { text: '快捷键', link: '/zh/guide/shortcuts' }
      ]
    },
    {
      text: '任务',
      items: [
        { text: '总览', link: '/zh/assays/' },
        { text: '悬尾实验', link: '/zh/assays/tail-suspension' },
        { text: '圆筒实验', link: '/zh/assays/cylinder' },
        { text: '步态分析', link: '/zh/assays/gait' },
        { text: '瘙痒（抓挠）', link: '/zh/assays/itch' },
        { text: '自发痛行为', link: '/zh/assays/pain' },
        { text: '自我理毛', link: '/zh/assays/grooming' },
        { text: '癫痫发作评分', link: '/zh/assays/seizure' }
      ]
    },
    {
      text: '原理',
      items: [
        { text: '姿态模型与预处理', link: '/zh/principles/pose' },
        { text: '验证与局限', link: '/zh/principles/validation' }
      ]
    },
    {
      text: '姿态模型',
      items: [
        { text: '模型与来源', link: '/zh/models/' },
        { text: 'CylinderPose7（可见光）', link: '/zh/models/cylinderpose7' },
        { text: 'PalmReaderPose8（近红外）', link: '/zh/models/palmreader8' },
        { text: '如何引用', link: '/zh/models/cite' }
      ]
    },
    {
      text: '参考',
      items: [
        { text: '资料库与文件', link: '/zh/reference/files' },
        { text: '常见问题与故障排除', link: '/zh/reference/faq' },
        { text: '参考文献', link: '/zh/reference/reading' },
        { text: '更新说明', link: '/zh/reference/changelog' }
      ]
    },
    {
      text: '关于',
      items: [
        { text: '源代码', link: '/zh/source' },
        { text: '隐私政策', link: '/zh/privacy' },
        { text: '支持', link: '/zh/support' },
        { text: '法律与声明', link: '/zh/legal' },
        { text: '无障碍', link: '/zh/accessibility' }
      ]
    }
  ]
}

export default defineConfig({
  base,
  title: 'RodentLimb',
  description: 'Limb pose and behavior scoring of mouse videos on Mac, iPhone and iPad — user manual',
  lastUpdated: false,
  cleanUrls: false,
  head: [
    ['link', { rel: 'icon', type: 'image/png', href: `${base}favicon-64.png` }],
    ['link', { rel: 'apple-touch-icon', href: `${base}apple-touch-icon.png` }],
    ['meta', { name: 'theme-color', content: '#1f7fe0' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: 'RodentLimb — limb pose and behavior scoring for mouse videos' }],
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
      description: 'Limb pose and behavior scoring of mouse videos on Mac, iPhone and iPad — user manual',
      themeConfig: {
        // The home pages are standalone (docs/public/index.html, docs/public/zh/index.html), not
        // VitePress pages: open them with a full page load.
        logoLink: { link: base, target: '_self' },
        nav: [
          {
            text: 'Manual',
            activeMatch: '^/(guide|assays|principles|reference)/',
            items: [
              { text: 'Getting started', link: '/guide/introduction' },
              { text: 'Using the Mac app', link: '/guide/import' },
              { text: 'Tasks', link: '/assays/' },
              { text: 'How it works', link: '/principles/pose' },
              { text: 'Reference', link: '/reference/files' }
            ]
          },
          { text: 'Pose models', link: '/models/', activeMatch: '^/models/' },
          { text: 'Source code', link: '/source' },
          { text: 'Support', link: '/support' }
        ],
        sidebar: sidebarEn(),
        outline: { level: [2, 3], label: 'On this page' },
        docFooter: { prev: 'Previous', next: 'Next' },
        editLink: {
          pattern: `${repo}/edit/main/docs/:path`,
          text: 'Edit this page on GitHub'
        },
        footer: {
          message: 'RodentLimb for Mac, iPhone and iPad · <a href="/RodentLimb/privacy.html">Privacy</a> · <a href="/RodentLimb/support.html">Support</a> · <a href="/RodentLimb/legal.html">Legal</a> · <a href="https://github.com/seesaw-earth/RodentLimb">GitHub</a>',
          copyright: '© 2026 Ziqing Shi'
        }
      }
    },
    zh: {
      label: '简体中文',
      lang: 'zh-CN',
      link: '/zh/',
      title: 'RodentLimb',
      description: '在 Mac、iPhone 和 iPad 上完成小鼠肢体姿态识别与行为评分 —— 使用手册',
      themeConfig: {
        logoLink: { link: `${base}zh/`, target: '_self' },
        nav: [
          {
            text: '手册',
            activeMatch: '^/zh/(guide|assays|principles|reference)/',
            items: [
              { text: '入门', link: '/zh/guide/introduction' },
              { text: '使用 Mac 版', link: '/zh/guide/import' },
              { text: '任务', link: '/zh/assays/' },
              { text: '原理', link: '/zh/principles/pose' },
              { text: '参考', link: '/zh/reference/files' }
            ]
          },
          { text: '姿态模型', link: '/zh/models/', activeMatch: '^/zh/models/' },
          { text: '源代码', link: '/zh/source' },
          { text: '支持', link: '/zh/support' }
        ],
        sidebar: sidebarZh(),
        outline: { level: [2, 3], label: '本页目录' },
        docFooter: { prev: '上一页', next: '下一页' },
        editLink: {
          pattern: `${repo}/edit/main/docs/:path`,
          text: '在 GitHub 上编辑此页'
        },
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
          message: 'RodentLimb · Mac、iPhone 与 iPad · <a href="/RodentLimb/zh/privacy.html">隐私政策</a> · <a href="/RodentLimb/zh/support.html">支持</a> · <a href="/RodentLimb/zh/legal.html">法律与声明</a> · <a href="https://github.com/seesaw-earth/RodentLimb">GitHub</a>',
          copyright: '© 2026 Ziqing Shi'
        }
      }
    }
  }
})
