#!/usr/bin/env python3
"""Builds the two home pages from home.template.html and the texts below.

    python3 tools/homepage/build_home.py

writes docs/public/index.html (English) and docs/public/zh/index.html (中文). Edit the texts here
and the layout in home.template.html, never the generated files. The clips themselves are made by
encode.sh / encode-all.sh in this folder.
"""
import html, json, pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
PUBLIC = HERE.parent.parent / 'docs' / 'public'

# Order of the showcase. "file" = output name of encode.sh (videos/<file>.mp4, .jpg, -thumb.jpg).
CLIPS = [
    {'file': 'mac-room-light', 'device': 'mac', 'light': 'room'},
    {'file': 'mac-near-infrared', 'device': 'mac', 'light': 'nir'},
    {'file': 'iphone-room-light', 'device': 'phone', 'light': 'room'},
    {'file': 'iphone-near-infrared', 'device': 'phone', 'light': 'nir'},
]

EN = {
    'lang': 'en',
    'root': '',
    'canonical': 'https://seesaw-earth.github.io/RodentLimb/',
    'other_lang': '中文', 'other_lang_code': 'zh-CN', 'other_lang_href': 'zh/',
    'manual': 'guide/getting-started.html',
    'title': 'RodentLimb | Limb pose and behavior scoring for mouse videos',
    'description': 'RodentLimb tracks the paws, nose, mouth and tail base of a mouse in every frame, on Mac, iPhone and iPad, and scores tail suspension, cylinder, gait, itch, pain, grooming and seizures. Nothing is uploaded.',
    'og_description': 'Limb pose and behavior scoring for mouse videos, on Mac, iPhone and iPad. Every frame is analyzed on the device.',
    'skip': 'Skip to content', 'nav_label': 'Page',
    'nav_watch': 'Watch', 'nav_workflow': 'Workflow', 'nav_models': 'Models', 'nav_tests': 'Tests', 'nav_cite': 'Cite', 'nav_manual': 'Manual',
    'hero_sub': 'Limb pose and behavior scoring for mouse videos, on Mac, iPhone and iPad. Every frame is analyzed on the device.',
    'author': 'Ziqing Shi, MD, PhD', 'affiliation': 'Yale School of Medicine',
    'btn_store': 'App Store', 'btn_source': 'Source code', 'btn_manual': 'User manual',
    'paw_lf': 'left fore', 'paw_rf': 'right fore', 'paw_lh': 'left hind', 'paw_rh': 'right hind',
    'watch_h': 'Watch it work',
    'watch_lede': 'Screen recordings of the app, in room light and in a near-infrared dark box. Keypoints are drawn in the colours the app uses for each paw.',
    'watch_larger': 'Watch this recording larger', 'watch_pause': 'Pause', 'watch_auto': 'Play all',
    'glance_h': 'At a glance',
    'glance_tldr': 'RodentLimb finds seven keypoints in every frame of a mouse video, keeps them, and scores the test you chose from them. Change a parameter and the result updates at once: the model never runs twice.',
    'spec': [
        ('Input', 'Ordinary video files (MP4, MOV). Most tests are filmed from below a clear floor; tail suspension from the front or side'),
        ('Keypoints', 'Four paws, tail base, nose and mouth, in every frame'),
        ('Tests', 'Seven: tail suspension, cylinder, gait, itch, spontaneous pain, self-grooming, seizures'),
        ('Runs on', 'Mac with macOS 14 or later, for overnight batches; iPhone and iPad with iOS 17 or later'),
        ('Output', 'Tables per task, behavior segments, a QC table, a methods paragraph, BORIS and DeepLabCut formats'),
        ('Privacy', 'No account, no network connection, no analytics. Videos are only read'),
    ],
    'wf_h': 'From video to figure',
    'wf_lede': 'Since version 1.4 everything starts from a task: choose the test first, then add its videos.',
    'steps': [
        ('Create a task', 'Choose the paradigm, then name the groups, timepoints and whether the task is blinded.'),
        ('Add videos', 'Drop videos or folders. Animal, group, timepoint and trial are read from the names; pick the model that matches the light.'),
        ('Track', 'The pose model reads every frame once, in a background queue with checkpoints: a pause or crash costs seconds, not hours.'),
        ('Check', 'Each video gets a quality verdict against the task\'s criteria; include or exclude the rest with a reason.'),
        ('Score and export', 'Replay every event on the video, relabel it, compare groups, then export tables and a methods paragraph.'),
    ],
    'models_h': 'Two models, chosen by the light',
    'models_lede': 'Pick the model when you add videos. Whatever the model, the same seven keypoints are stored, so every task, check and export works the same way.',
    'models': [
        {'cls': '', 'use': 'Room light', 'name': 'CylinderPose7',
         'text': 'The default. Ordinary room-light video, colour or grayscale, usually filmed from below a clear floor.',
         'kps': [('lf', 'left fore'), ('rf', 'right fore'), ('lh', 'left hind'), ('rh', 'right hind'), ('tail', 'tail base'), ('nose', 'nose'), ('mouth', 'mouth')],
         'nokp': [],
         'facts': [('Trained on', '543 human-labelled frames and 20,000 cleaned DeepLabCut predictions of cylinder-test recordings'),
                   ('Tested on', '80 held-out frames: mean error 0.035 body lengths, 96 % of points within 0.1 body lengths'),
                   ('In the app', 'YOLO26s-pose, 640 px, half-precision Core ML, 19 MB')],
         'link': 'models/cylinderpose7.html'},
        {'cls': 'nir', 'use': 'Near-infrared', 'name': 'PalmReaderPose8',
         'text': 'For dark-box rigs: filmed from below in the dark, under near-infrared light.',
         'kps': [('lf', 'left fore'), ('rf', 'right fore'), ('lh', 'left hind'), ('rh', 'right hind'), ('tail', 'tail base'), ('nose', 'snout')],
         'nokp': [('mouth', 'mouth')],
         'facts': [('Trained on', '409 human-labelled frames from the published training set of Barkai et al. (2025)'),
                   ('Tested on', '37 held-out frames: median error 9.8 px, 77 % of points within 0.1 body lengths'),
                   ('In the app', 'YOLO26s-pose, 640 px, 8-bit Core ML, 9.8 MB')],
         'link': 'models/palmreader8.html'},
    ],
    'models_more': 'Data, training and what to cite',
    'models_note': 'The two test results come from different videos and are not comparable with each other. Where a task needs the mouth, near-infrared videos use the nose instead.',
    'tests_h': 'Seven tests from one pipeline',
    'tests_lede': 'Each test turns the keypoints into its own measures. Every detected event can be replayed on the video and relabelled.',
    'tests_col_test': 'Test', 'tests_col_kind': 'Kind', 'tests_col_measures': 'Main measures',
    'kind_limb': 'Limb', 'kind_behavior': 'Behavior',
    'tests': [
        ('tail-suspension', 'Tail suspension', 'limb', 'Immobility time and %, latency, bouts, per-minute profile, tail climbing, estimated clasping score'),
        ('cylinder', 'Cylinder test', 'limb', 'Left, right and both-paw wall contacts, contralateral use, asymmetry index'),
        ('gait', 'Gait analysis', 'limb', 'Stride, stance, swing, duty factor, base of support, interlimb phase, gait pattern, speed-matched values'),
        ('itch', 'Itch (scratching)', 'behavior', 'Scratching bouts, time, latency and trains after a pruritogen, which hind paw, time course'),
        ('pain', 'Spontaneous pain', 'behavior', 'Licking or biting and flinching of the injected paw, formalin phase I / II, time course'),
        ('grooming', 'Self-grooming', 'behavior', 'Grooming time, bouts, latency, body regions, interrupted bouts and incorrect transitions'),
        ('seizure', 'Seizure scoring', 'behavior', 'Myoclonic jerks, clonic and tonic-clonic seizures, latencies, estimated Racine stage'),
    ],
    'trio': [
        ('Same numbers on iPhone and Mac', 'Both apps share one analysis layer and one library format. A library copied from an iPhone opens on the Mac with the same results.', 'guide/iphone.html', 'iPhone & iPad'),
        ('Nothing leaves the device', 'No account, no analytics, no network connection. Videos stay where they are, and exports are files you save yourself.', 'privacy.html', 'Privacy policy'),
        ('Know the limits', 'Keypoints are estimates. Check the quality verdicts and score a sample of videos by hand before you trust a new setup.', 'principles/validation.html', 'Validation & limits'),
    ],
    'cite_h': 'Cite RodentLimb',
    'cite_lede': 'If RodentLimb contributes to published work, cite the version you used, and the pose model\'s software and training data: <a href="models/cite.html">how to cite</a>.',
    'cite_copy': 'Copy', 'copied': 'Copied', 'copy_failed': 'Select and copy',
    'foot_made': 'Made by Ziqing Shi at Yale School of Medicine. Open source under the GNU AGPL-3.0.',
    'foot_label': 'Site', 'foot_models': 'Pose models', 'foot_support': 'Support', 'foot_privacy': 'Privacy', 'foot_legal': 'Legal',
    'close': 'Close',
    'play': 'Play', 'pause': 'Pause',
    'missing': 'This clip has not been encoded yet.',
    'clips': [
        {'title': 'Room light, on the Mac', 'short': 'Room light',
         'text': 'RodentLimb for Mac tracking an ordinary room-light video with CylinderPose7: paws, nose, mouth and tail base on every frame.',
         'tags': ['CylinderPose7', '7 keypoints', 'Batch queue']},
        {'title': 'Near-infrared, on the Mac', 'short': 'Near-infrared',
         'text': 'The same app with a dark-box video filmed from below under near-infrared light, tracked with PalmReaderPose8.',
         'tags': ['PalmReaderPose8', 'Dark box', 'Filmed from below']},
        {'title': 'Room light, on iPhone', 'short': 'Room light',
         'text': 'The iPhone app runs the same model and the same analysis code, so a video gives the same numbers on both.',
         'tags': ['CylinderPose7', 'Same analysis code']},
        {'title': 'Near-infrared, on iPhone', 'short': 'Near-infrared',
         'text': 'Near-infrared tracking on the phone. Like everything else in RodentLimb, it runs on the device.',
         'tags': ['PalmReaderPose8', 'On the device']},
    ],
    'light_room': 'Room light', 'light_nir': 'Near-infrared', 'dev_mac': 'Mac', 'dev_phone': 'iPhone',
}

ZH = {
    'lang': 'zh-CN',
    'root': '../',
    'canonical': 'https://seesaw-earth.github.io/RodentLimb/zh/',
    'other_lang': 'English', 'other_lang_code': 'en', 'other_lang_href': '../',
    'manual': 'guide/getting-started.html',
    'title': 'RodentLimb | 小鼠视频的肢体姿态与行为评分',
    'description': 'RodentLimb 在 Mac、iPhone 和 iPad 上逐帧识别小鼠的四只爪、鼻、口和尾根，并完成悬尾、圆筒、步态、瘙痒、疼痛、理毛和癫痫评分。不上传任何数据。',
    'og_description': '在 Mac、iPhone 和 iPad 上完成小鼠视频的肢体姿态与行为评分。每一帧都在本机分析。',
    'skip': '跳到正文', 'nav_label': '页面',
    'nav_watch': '演示', 'nav_workflow': '流程', 'nav_models': '模型', 'nav_tests': '实验', 'nav_cite': '引用', 'nav_manual': '手册',
    'hero_sub': '在 Mac、iPhone 和 iPad 上完成小鼠视频的肢体姿态与行为评分。每一帧都在本机分析。',
    'author': 'Ziqing Shi, MD, PhD', 'affiliation': '耶鲁大学医学院',
    'btn_store': 'App Store', 'btn_source': '源代码', 'btn_manual': '使用手册',
    'paw_lf': '左前爪', 'paw_rf': '右前爪', 'paw_lh': '左后爪', 'paw_rh': '右后爪',
    'watch_h': '看它如何工作',
    'watch_lede': 'App 的录屏，分别在室内光和近红外暗箱中。关键点按 App 中每只爪的颜色绘制。',
    'watch_larger': '放大观看', 'watch_pause': '暂停', 'watch_auto': '连续播放',
    'glance_h': '一览',
    'glance_tldr': 'RodentLimb 在小鼠视频的每一帧中找出七个关键点并保存下来，再据此为你选择的实验评分。修改参数时结果立即更新：模型不需要再运行一次。',
    'spec': [
        ('输入', '普通视频文件（MP4、MOV）。多数实验从透明底板下方拍摄；悬尾从正面或侧面拍摄'),
        ('关键点', '四只爪、尾根、鼻和口，每一帧都有'),
        ('实验', '七项：悬尾、圆筒、步态、瘙痒、自发痛、自我理毛、癫痫发作'),
        ('运行于', 'macOS 14 或更高版本的 Mac，适合通宵批处理；iOS 17 或更高版本的 iPhone 和 iPad'),
        ('输出', '每个任务的数据表、行为片段、QC 表、方法学文字，以及 BORIS 和 DeepLabCut 格式'),
        ('隐私', '无需账号，不联网，不做统计。视频只被读取'),
    ],
    'wf_h': '从视频到图表',
    'wf_lede': '从 1.4 版起，一切都从任务开始：先选实验，再添加它的视频。',
    'steps': [
        ('新建任务', '选择范式，再填写组别、时间点以及是否盲法。'),
        ('添加视频', '拖入视频或文件夹。动物、组别、时间点和试次从文件名读出；按光照选择模型。'),
        ('识别', '姿态模型在带检查点的后台队列中把每一帧读一遍：暂停或崩溃只损失几秒，而不是几小时。'),
        ('检查', '每段视频按任务的标准得到质量结论；其余的由你纳入或排除，并写明原因。'),
        ('评分与导出', '在视频上回放每个事件并修改标签、比较组间差异，然后导出数据表和方法学文字。'),
    ],
    'models_h': '两个模型，按光照选择',
    'models_lede': '添加视频时选择模型。无论用哪个模型，保存的都是同样的七个关键点，所有任务、检查和导出都一样。',
    'models': [
        {'cls': '', 'use': '室内光', 'name': 'CylinderPose7',
         'text': '默认模型。普通室内光视频（彩色或灰度），通常从透明底板下方拍摄。',
         'kps': [('lf', '左前爪'), ('rf', '右前爪'), ('lh', '左后爪'), ('rh', '右后爪'), ('tail', '尾根'), ('nose', '鼻'), ('mouth', '口')],
         'nokp': [],
         'facts': [('训练数据', '圆筒实验录像中的 543 帧人工标注和 20,000 帧清洗后的 DeepLabCut 预测'),
                   ('测试结果', '80 帧留出数据：平均误差 0.035 个体长，96 % 的点在 0.1 个体长以内'),
                   ('App 中', 'YOLO26s-pose，640 像素，半精度 Core ML，19 MB')],
         'link': 'models/cylinderpose7.html'},
        {'cls': 'nir', 'use': '近红外', 'name': 'PalmReaderPose8',
         'text': '用于暗箱装置：黑暗中从下方拍摄、近红外光照明。',
         'kps': [('lf', '左前爪'), ('rf', '右前爪'), ('lh', '左后爪'), ('rh', '右后爪'), ('tail', '尾根'), ('nose', '吻端')],
         'nokp': [('mouth', '口')],
         'facts': [('训练数据', 'Barkai 等（2025）公开训练集中的 409 帧人工标注'),
                   ('测试结果', '37 帧留出数据：中位误差 9.8 像素，77 % 的点在 0.1 个体长以内'),
                   ('App 中', 'YOLO26s-pose，640 像素，8 位 Core ML，9.8 MB')],
         'link': 'models/palmreader8.html'},
    ],
    'models_more': '数据、训练与引用方式',
    'models_note': '两个测试结果来自不同的视频，彼此不可比较。需要口的任务在近红外视频中改用鼻。',
    'tests_h': '一条流程，七项实验',
    'tests_lede': '每项实验把关键点转换成各自的指标。每个检测到的事件都可以在视频上回放并修改标签。',
    'tests_col_test': '实验', 'tests_col_kind': '类型', 'tests_col_measures': '主要指标',
    'kind_limb': '肢体', 'kind_behavior': '行为',
    'tests': [
        ('tail-suspension', '悬尾实验', 'limb', '不动时间与百分比、潜伏期、不动回合、逐分钟曲线、爬尾、估计的后肢抱握评分'),
        ('cylinder', '圆筒实验', 'limb', '左爪、右爪和双爪触壁次数，对侧使用率，不对称指数'),
        ('gait', '步态分析', 'limb', '步幅、支撑相、摆动相、占空比、支撑基宽、肢间相位、步态模式、速度匹配值'),
        ('itch', '瘙痒（抓挠）', 'behavior', '致痒剂注射后的抓挠回合、时间、潜伏期和抓挠串，哪只后爪，时间进程'),
        ('pain', '自发痛行为', 'behavior', '注射爪的舔咬和缩爪/甩爪，福尔马林 I / II 相，时间进程'),
        ('grooming', '自我理毛', 'behavior', '理毛时间、回合、潜伏期、身体部位、中断回合与错误转换'),
        ('seizure', '癫痫发作评分', 'behavior', '肌阵挛抽动、阵挛和强直-阵挛发作、潜伏期、估计的 Racine 分级'),
    ],
    'trio': [
        ('iPhone 与 Mac 结果相同', '两个 App 共用同一层分析代码和同样的资料库格式。从 iPhone 拷贝的资料库在 Mac 上打开，结果完全相同。', 'guide/iphone.html', 'iPhone 与 iPad'),
        ('数据不离开设备', '无需账号，不做统计，不联网。视频留在原处，导出的文件由你自己保存。', 'privacy.html', '隐私政策'),
        ('了解局限', '关键点是估计值。在信任新的拍摄设置之前，请查看质量结论，并人工评分一部分视频。', 'principles/validation.html', '验证与局限'),
    ],
    'cite_h': '引用 RodentLimb',
    'cite_lede': '如果 RodentLimb 对发表的工作有贡献，请引用所用版本，以及姿态模型的软件和训练数据：<a href="models/cite.html">如何引用</a>。',
    'cite_copy': '拷贝', 'copied': '已拷贝', 'copy_failed': '请选中后拷贝',
    'foot_made': '由耶鲁大学医学院 Ziqing Shi 制作。以 GNU AGPL-3.0 开源。',
    'foot_label': '网站', 'foot_models': '姿态模型', 'foot_support': '支持', 'foot_privacy': '隐私', 'foot_legal': '法律',
    'close': '关闭',
    'play': '播放', 'pause': '暂停',
    'missing': '这段视频尚未生成。',
    'clips': [
        {'title': 'Mac 上的室内光视频', 'short': '室内光',
         'text': 'RodentLimb for Mac 用 CylinderPose7 识别普通室内光视频：每一帧都标出四爪、鼻、口和尾根。',
         'tags': ['CylinderPose7', '7 个关键点', '批处理队列']},
        {'title': 'Mac 上的近红外视频', 'short': '近红外',
         'text': '同一个 App，处理暗箱中从下方、在近红外光下拍摄的视频，使用 PalmReaderPose8。',
         'tags': ['PalmReaderPose8', '暗箱', '从下方拍摄']},
        {'title': 'iPhone 上的室内光视频', 'short': '室内光',
         'text': 'iPhone 版运行同样的模型和同样的分析代码，同一段视频在两端得到相同的数字。',
         'tags': ['CylinderPose7', '同一套分析代码']},
        {'title': 'iPhone 上的近红外视频', 'short': '近红外',
         'text': '在手机上识别近红外视频。和 RodentLimb 的其他部分一样，全部在本机运行。',
         'tags': ['PalmReaderPose8', '本机运行']},
    ],
    'light_room': '室内光', 'light_nir': '近红外', 'dev_mac': 'Mac', 'dev_phone': 'iPhone',
}

esc = html.escape


def render(L):
    t = (HERE / 'home.template.html').read_text()
    v = {k: val for k, val in L.items() if isinstance(val, str)}
    v['spec_rows'] = '\n      '.join(f'<div><dt>{esc(a)}</dt><dd>{esc(b)}</dd></div>' for a, b in L['spec'])
    v['steps'] = '\n      '.join(f'<li><h3>{esc(a)}</h3><p>{esc(b)}</p></li>' for a, b in L['steps'])
    models = []
    for m in L['models']:
        kps = ''.join(f'<li><i style="--c:var(--{k})"></i>{esc(n)}</li>' for k, n in m['kps'])
        kps += ''.join(f'<li class="no"><i style="--c:var(--{k})"></i>{esc(n)}</li>' for k, n in m['nokp'])
        facts = ''.join(f'<div><dt>{esc(a)}</dt><dd>{esc(b)}</dd></div>' for a, b in m['facts'])
        models.append(f'<article class="model {m["cls"]}"><span class="use"><i></i>{esc(m["use"])}</span>'
                      f'<h3>{esc(m["name"])}</h3><p>{esc(m["text"])}</p><ul class="kps">{kps}</ul>'
                      f'<dl class="facts">{facts}</dl><a class="more" href="{m["link"]}">{esc(L["models_more"])}</a></article>')
    v['models'] = '\n      '.join(models)
    rows = []
    for slug, name, kind, measures in L['tests']:
        tag = f'<span class="tag{" b" if kind == "behavior" else ""}">{esc(L["kind_" + kind])}</span>'
        rows.append(f'<tr><th scope="row"><a href="assays/{slug}.html">{esc(name)}</a></th><td class="kind">{tag}</td><td>{esc(measures)}</td></tr>')
    v['test_rows'] = '\n          '.join(rows)
    v['trio'] = '\n      '.join(f'<div><h3>{esc(a)}</h3><p>{esc(b)} <a href="{h}">{esc(lk)}</a></p></div>' for a, b, h, lk in L['trio'])
    clips = []
    for c, txt in zip(CLIPS, L['clips']):
        clips.append({**c, **txt,
                      'lightLabel': L['light_' + c['light']],
                      'deviceLabel': L['dev_' + c['device']]})
    v['clips_json'] = json.dumps(clips, ensure_ascii=False, indent=2)
    v['root_json'] = json.dumps(L['root'])
    v['js_strings'] = json.dumps({'play': L['play'], 'pause': L['pause'], 'copy': L['cite_copy'], 'copied': L['copied'],
                                  'copyFailed': L['copy_failed'], 'missing': L['missing']}, ensure_ascii=False)
    # cite_lede holds a link: inserted as written (trusted text in this file)
    out = re.sub(r'\{\{(\w+)\}\}', lambda m: v[m.group(1)] if m.group(1) in ('spec_rows', 'steps', 'models', 'test_rows', 'trio',
                 'clips_json', 'root_json', 'js_strings', 'cite_lede') else esc(v[m.group(1)], quote=True), t)
    return out


if __name__ == '__main__':
    (PUBLIC / 'index.html').write_text(render(EN))
    (PUBLIC / 'zh').mkdir(exist_ok=True)
    (PUBLIC / 'zh' / 'index.html').write_text(render(ZH))
    print('wrote', PUBLIC / 'index.html', 'and', PUBLIC / 'zh' / 'index.html')
