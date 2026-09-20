from pathlib import Path
from html import escape

OUT = Path(__file__).parent / "assets"

W, H = 390, 844


def svg(title, body):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<title>{escape(title)}</title>
<rect width="390" height="844" fill="#F6F7F9"/>
<style>
text{{font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Helvetica Neue',Arial,sans-serif;fill:#111827}}
.muted{{fill:#7A8493}} .blue{{fill:#1467E8}} .green{{fill:#18885A}} .orange{{fill:#C46A18}}
.small{{font-size:12px}} .body{{font-size:15px}} .label{{font-size:13px;font-weight:600}}
.title{{font-size:28px;font-weight:750}} .h2{{font-size:20px;font-weight:700}} .h3{{font-size:17px;font-weight:650}}
.white{{fill:#fff}} .mono{{font-family:'SF Mono',Menlo,monospace}}
</style>
<text x="24" y="34" class="small muted">20:38</text>
{body}
</svg>'''


def card(x, y, w, h, rx=18, fill="#FFFFFF", stroke="#E7E9ED"):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}"/>'


def pill(x, y, w, text, active=False):
    fill = "#FFFFFF" if active else "transparent"
    ink = "#111827" if active else "#7A8493"
    shadow = '<rect x="{0}" y="{1}" width="{2}" height="36" rx="9" fill="#FFFFFF" stroke="#E7E9ED"/>'.format(x, y, w) if active else ""
    return shadow + f'<text x="{x + w/2}" y="{y+23}" text-anchor="middle" font-size="13" font-weight="600" fill="{ink}">{escape(text)}</text>'


def bottom_nav(active):
    items = [("助手", 39), ("今天", 115), ("任务", 191), ("随手记", 267), ("更多插件", 343)]
    s = '<rect x="0" y="770" width="390" height="74" fill="#FFFFFF" stroke="#E7E9ED"/>'
    icons = {
        "助手": '<path d="M0 -10L2 -3L8 0L2 3L0 10L-2 3L-8 0L-2 -3Z M8 -10v5 M5.5 -7.5h5"/>',
        "今天": '<rect x="-10" y="-8" width="20" height="18" rx="3"/><path d="M-10 -2h20 M-5 -11v6 M5 -11v6 M-5 3h2 M2 3h2 M-5 7h2"/>',
        "任务": '<path d="M0 -10L11 -5L0 0L-11 -5Z M-11 0L0 5L11 0 M-11 5L0 10L11 5"/>',
        "随手记": '<path d="M2 -8h-10v18h18V0 M-2 4l1 -5L7 -9L11 -5L3 3Z M5 -7l4 4"/>',
        "更多插件": '<circle r="10"/><circle cx="-5" r=".7"/><circle r=".7"/><circle cx="5" r=".7"/>',
    }
    for name, x in items:
        c = "#1467E8" if name == active else "#7A8493"
        s += f'<g transform="translate({x},792)" fill="none" stroke="{c}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">{icons[name]}</g>'
        s += f'<text x="{x}" y="819" text-anchor="middle" font-size="10" style="fill:{c}">{name}</text>'
    return s


pages = {}

pages["today.svg"] = svg("今天 · 专注与今日时间线", f'''
<rect width="390" height="770" fill="#FAF9F5"/>
<text x="24" y="34" class="small muted">20:38</text>
<text x="24" y="88" font-size="38" font-weight="800">今天</text>
<text x="24" y="117" class="label muted">9月20日 · 星期日</text>
{card(320,56,46,46,19,"#FFFEFC")}
<path d="M334 71h18 M334 78h18 M334 85h18" stroke="#575C69" stroke-width="2" stroke-linecap="round"/>
{card(22,140,346,208,34,"#FFFEFC")}
<rect x="40" y="157" width="82" height="27" rx="13" fill="#E8F7F2"/>
<text x="81" y="175" text-anchor="middle" font-size="12" style="fill:#08A380">正在发生</text>
<text x="40" y="214" class="h2">优化页面评审</text>
<text x="40" y="263" font-size="40" font-weight="700" class="mono">42:00</text>
<text x="346" y="240" text-anchor="end" class="small muted">累计 3小时16分</text>
<text x="346" y="262" text-anchor="end" class="small muted">今日 1小时36分</text>
<rect x="40" y="288" width="90" height="42" rx="16" fill="#0E0F12"/>
<text x="85" y="315" text-anchor="middle" class="body white">Ⅱ 暂停</text>
<rect x="140" y="288" width="106" height="42" rx="16" fill="#E8F2FF"/>
<path d="M173 302q-15 -5 -13 10q11 5 13 -10 M160 315l11 -11" fill="none" stroke="#0A57D1" stroke-width="1.6"/>
<text x="201" y="315" text-anchor="middle" class="h3 blue">Zen</text>
<rect x="256" y="288" width="90" height="42" rx="16" fill="#E8F7F2"/><text x="301" y="315" text-anchor="middle" class="body green">✓ 完成</text>
<text x="24" y="383" class="h2">执行中 · 1</text>
<text x="366" y="383" text-anchor="end" class="small blue">20:38</text>
<text x="72" y="427" text-anchor="end" class="small muted">20:20</text>
{card(85,402,281,86,20,"#FFFEFC")}
<circle cx="103" cy="424" r="5" fill="#08A380"/>
<text x="117" y="429" class="body">整理素材</text>
<text x="350" y="427" text-anchor="end" class="small blue">下一项</text>
<text x="104" y="452" class="small green">计时中 · 本段 18:00</text>
<text x="104" y="475" class="small muted">累计 58分 · 今日 18分</text>
<g transform="translate(0,-96)">
<text x="24" y="622" class="h2">今日规划 · 3</text>
<text x="366" y="622" text-anchor="end" class="small muted">暂停 / 未开始 / 已完成</text>
<text x="72" y="666" text-anchor="end" class="small muted">21:00</text>
<path d="M48 676v88" stroke="#E2E0DC"/>
{card(85,642,281,114,24,"#FFFEFC")}
<circle cx="103" cy="665" r="5" fill="#F56314"/>
<text x="117" y="670" class="body">查看同步方案进度</text>
<text x="104" y="694" class="small muted">已暂停 · 累计 1小时20分 · 今日 20分</text>
<text x="104" y="714" font-size="11" class="muted">最近 15:10–15:30</text>
<rect x="104" y="723" width="68" height="25" rx="9" fill="#0E63E6"/><text x="138" y="740" text-anchor="middle" class="small white">▷ 继续</text>
<rect x="182" y="723" width="62" height="25" rx="9" fill="#E8F2FF"/><text x="213" y="740" text-anchor="middle" class="small blue">Zen</text>
<rect x="254" y="723" width="68" height="25" rx="9" fill="#F4F2EE"/><text x="288" y="740" text-anchor="middle" class="small">✓ 完成</text>
<text x="72" y="791" text-anchor="end" class="small muted">22:00</text>
{card(85,770,281,72,20,"#FFFFFF")}
<circle cx="103" cy="791" r="5" fill="#F58278"/>
<text x="117" y="796" class="body">阅读与整理</text>
<text x="104" y="821" class="small muted">未开始 · 累计 0分 · 今日 0分</text>
<text x="72" y="889" text-anchor="end" class="small muted">19:00</text>
{card(85,864,281,72,20,"#F4F2EE")}
<circle cx="103" cy="886" r="6" fill="#339E6E"/><path d="M100 886l2 2l4 -4" stroke="white" fill="none"/>
<text x="117" y="891" class="body muted" text-decoration="line-through">整理用户反馈</text>
<text x="104" y="915" class="small muted">已完成 · 累计 45分 · 今日 45分</text>
</g>
<circle cx="334" cy="916" r="28" fill="#0E63E6"/><path d="M324 916h20 M334 906v20" stroke="white" stroke-width="2.5" stroke-linecap="round"/>
<g transform="translate(0,196)">{bottom_nav("今天")}</g>
''').replace('height="844"', 'height="1040"').replace('viewBox="0 0 390 844"', 'viewBox="0 0 390 1040"').replace('height="770" fill="#FAF9F5"', 'height="966" fill="#FAF9F5"')

def tasks_page(kind):
    names = ["列表", "结构", "时间", "鱼骨"]
    seg = '<rect x="91" y="48" width="275" height="44" rx="12" fill="#EEF1F5"/>'
    x = 95
    widths = [65,65,65,65]
    for n,w in zip(names,widths):
        seg += pill(x,52,w,n,n==kind); x += 67
    header = '<text x="24" y="80" class="title">任务</text>' + seg
    if kind == "列表":
        content = f'''<text x="24" y="126" class="small muted">全部任务 · 12</text>
{card(20,146,350,72)}<circle cx="47" cy="182" r="10" fill="none" stroke="#1467E8" stroke-width="2"/><text x="70" y="177" class="body">完成 Mac 端完整版</text><text x="70" y="199" class="small muted">Tough Trial · 产品</text><text x="350" y="188" text-anchor="end" class="h2 muted">›</text>
{card(20,230,350,92)}<circle cx="47" cy="268" r="10" fill="none" stroke="#1467E8" stroke-width="2"/><text x="70" y="258" class="body">优化任务编辑体验</text><text x="70" y="281" class="small muted">用户体验 · 3 个子任务</text><text x="70" y="302" class="small muted">今天</text><text x="350" y="278" text-anchor="end" class="h2 muted">›</text>
{card(20,334,350,72)}<circle cx="47" cy="370" r="10" fill="none" stroke="#1467E8" stroke-width="2"/><text x="70" y="365" class="body">研究 Obsidian Sync</text><text x="70" y="387" class="small muted">同步 · 研究</text><text x="350" y="376" text-anchor="end" class="h2 muted">›</text>'''
    elif kind == "结构":
        content = f'''<text x="24" y="126" class="small muted">目标 → 任务 → 子任务</text>
{card(20,146,350,258)}<text x="38" y="178" class="label blue">▾ Tough Trial</text><line x1="48" y1="190" x2="48" y2="376" stroke="#D8DFEA" stroke-width="2"/>
<circle cx="70" cy="220" r="8" fill="none" stroke="#1467E8" stroke-width="2"/><text x="91" y="225" class="body">完善跨端同步</text>
<circle cx="94" cy="262" r="7" fill="none" stroke="#7A8493" stroke-width="2"/><text x="114" y="267" class="body">GitHub 同步</text>
<circle cx="94" cy="302" r="7" fill="none" stroke="#7A8493" stroke-width="2"/><text x="114" y="307" class="body">WebDAV / NAS 预留</text>
<circle cx="70" cy="348" r="8" fill="none" stroke="#1467E8" stroke-width="2"/><text x="91" y="353" class="body">改善任务体验</text>'''
    elif kind == "时间":
        content = f'''<text x="24" y="126" class="small muted">本周 · 9月14–20日</text>
<rect x="20" y="146" width="350" height="322" rx="20" fill="#FFFFFF" stroke="#E7E9ED"/>
<line x1="68" y1="172" x2="68" y2="446" stroke="#E7E9ED"/><text x="43" y="199" class="small muted">09</text><text x="43" y="265" class="small muted">12</text><text x="43" y="331" class="small muted">15</text><text x="43" y="397" class="small muted">18</text>
<text x="100" y="172" class="small muted">一</text><text x="151" y="172" class="small muted">二</text><text x="202" y="172" class="small muted">三</text><text x="253" y="172" class="small muted">四</text><text x="304" y="172" class="small blue">今</text>
<rect x="285" y="204" width="60" height="70" rx="10" fill="#E8F0FF"/><text x="315" y="225" text-anchor="middle" class="small blue">整理反馈</text><text x="315" y="244" text-anchor="middle" class="small blue">10:00</text>
<rect x="183" y="298" width="61" height="92" rx="10" fill="#EEF7F2"/><text x="214" y="319" text-anchor="middle" class="small green">Mac App</text><text x="214" y="338" text-anchor="middle" class="small green">14:30</text>'''
    else:
        content = f'''<text x="24" y="126" class="small muted">按目标看依赖与推进方向</text>
<line x1="72" y1="286" x2="332" y2="286" stroke="#111827" stroke-width="3"/>
<line x1="136" y1="286" x2="174" y2="218" stroke="#1467E8" stroke-width="2"/><line x1="136" y1="286" x2="174" y2="354" stroke="#1467E8" stroke-width="2"/>
<line x1="226" y1="286" x2="264" y2="218" stroke="#18885A" stroke-width="2"/><line x1="226" y1="286" x2="264" y2="354" stroke="#18885A" stroke-width="2"/>
<circle cx="72" cy="286" r="24" fill="#111827"/><text x="72" y="291" text-anchor="middle" class="small white">目标</text>
{card(155,182,118,45,12)}<text x="214" y="210" text-anchor="middle" class="small">同步系统</text>
{card(155,344,118,45,12)}<text x="214" y="372" text-anchor="middle" class="small">任务体验</text>
{card(245,182,112,45,12)}<text x="301" y="210" text-anchor="middle" class="small">GitHub</text>
{card(245,344,112,45,12)}<text x="301" y="372" text-anchor="middle" class="small">编辑器</text>'''
    return svg(f"任务 · {kind}", header + content + '<circle cx="334" cy="704" r="28" fill="#1467E8"/><text x="334" y="712" text-anchor="middle" font-size="28" class="white">+</text>' + bottom_nav("任务"))

for kind, filename in [("列表","tasks-list.svg"),("结构","tasks-structure.svg"),("时间","tasks-time.svg"),("鱼骨","tasks-fishbone.svg")]:
    pages[filename] = tasks_page(kind)

pages["assistant.svg"] = svg("助手", f'''
<text x="24" y="78" class="title">助手</text><circle cx="340" cy="68" r="18" fill="#FFFFFF" stroke="#E7E9ED"/><text x="340" y="73" text-anchor="middle" class="h3">＋</text>
<text x="24" y="118" class="small muted">最近对话</text>
{card(20,136,350,78)}<text x="38" y="166" class="body">同步方案和 Obsidian Sync</text><text x="38" y="190" class="small muted">今天 · 4 条消息</text><text x="350" y="180" text-anchor="end" class="h2 muted">›</text>
{card(20,226,350,78)}<text x="38" y="256" class="body">页面评审与模块设计</text><text x="38" y="280" class="small muted">昨天 · 11 条消息</text><text x="350" y="270" text-anchor="end" class="h2 muted">›</text>
<text x="24" y="354" class="h2">想一起处理什么？</text><text x="24" y="380" class="body muted">说说要做的事，或直接录一段语音。</text>
<rect x="20" y="418" width="350" height="128" rx="22" fill="#FFFFFF" stroke="#DCE2EA"/><text x="38" y="452" class="body muted">输入消息…</text><circle cx="52" cy="514" r="18" fill="#F0F3F7"/><text x="52" y="519" text-anchor="middle" class="body">＋</text><circle cx="310" cy="514" r="18" fill="#F0F3F7"/><text x="310" y="519" text-anchor="middle" class="small">🎙</text><circle cx="348" cy="514" r="18" fill="#1467E8"/><text x="348" y="519" text-anchor="middle" class="white">↑</text>
{bottom_nav("助手")}
''')

pages["capture.svg"] = svg("随手记", f'''
<text x="24" y="78" class="title">随手记</text><text x="366" y="76" text-anchor="end" class="body blue">新记录</text>
<rect x="20" y="104" width="350" height="42" rx="11" fill="#E9EDF2"/>{pill(23,107,84,"记录",True)}{pill(110,107,84,"记账")}{pill(197,107,84,"收纳")}{pill(284,107,82,"灵感")}
<text x="24" y="190" class="h2">想到什么，就记下来。</text><text x="24" y="216" class="small muted">账单、复盘、灵感和待办，可以写在一起。</text>
<rect x="20" y="240" width="350" height="210" rx="20" fill="#FFFFFF" stroke="#DCE2EA"/><text x="38" y="276" class="body muted">比如：午餐花了 38 元。今天沟通很顺畅，</text><text x="38" y="300" class="body muted">下次先列出重点。还想拍一期早餐视频……</text>
<text x="38" y="416" class="small blue">图片</text><text x="92" y="416" class="small blue">手写</text><text x="146" y="416" class="small blue">文件</text><text x="318" y="416" class="small blue">说一段</text>
<rect x="20" y="470" width="350" height="48" rx="14" fill="#1467E8"/><text x="195" y="501" text-anchor="middle" class="body white">整理这段内容</text>
<text x="195" y="556" text-anchor="middle" class="small muted">仅保存在本机 · 原文与附件可回看</text>
{bottom_nav("随手记")}
''')

pages["recall.svg"] = svg("回想", f'''
<circle cx="42" cy="76" r="18" fill="#FFFFFF" stroke="#E7E9ED"/><text x="42" y="81" text-anchor="middle" class="body">⛶</text><text x="72" y="73" class="h2">回想</text><text x="72" y="94" class="small muted">9月20日 · 星期日</text>
<rect x="238" y="54" width="128" height="38" rx="9" fill="#E9EDF2"/>{pill(241,57,60,"文字",True)}{pill(303,57,60,"手写")}
<rect x="20" y="122" width="48" height="554" rx="18" fill="#F0F2F5"/>
<text x="44" y="164" text-anchor="middle" class="small muted">五</text><text x="44" y="184" text-anchor="middle" class="body">18</text><rect x="25" y="204" width="38" height="58" rx="19" fill="#111827"/><text x="44" y="226" text-anchor="middle" class="small white">日</text><text x="44" y="247" text-anchor="middle" class="body white">20</text><text x="44" y="294" text-anchor="middle" class="small muted">一</text><text x="44" y="315" text-anchor="middle" class="body muted">21</text>
<rect x="84" y="122" width="286" height="554" rx="20" fill="#FFFFFF" stroke="#E7E9ED"/><text x="106" y="160" class="body muted">今天发生了什么？</text><text x="106" y="197" class="body">把真实发生的事情写下来。</text><text x="106" y="227" class="body">可以引用任务、日程和随手记作为线索。</text><line x1="106" y1="256" x2="348" y2="256" stroke="#E7E9ED"/>
<text x="106" y="296" class="small muted">今天的线索</text><text x="106" y="326" class="body">完成 3 个任务 · 专注 2h 10m</text><text x="106" y="354" class="body">2 条随手记 · 1 笔支出</text>
<rect x="84" y="698" width="286" height="44" rx="14" fill="#111827"/><text x="227" y="726" text-anchor="middle" class="body white">保存今天的回想</text>
''')

pages["finance.svg"] = svg("财务 · 理账计划", f'''
<text x="24" y="78" class="title">理账计划</text><text x="366" y="76" text-anchor="end" class="body blue">统计</text>
<text x="24" y="124" class="h2">订阅与还款</text><text x="366" y="124" text-anchor="end" class="body blue">＋ 添加</text><text x="24" y="150" class="small muted">到期提醒；确认已支付后才记入流水。</text>
{card(20,170,350,82)}<text x="38" y="200" class="body">ChatGPT Pro</text><text x="38" y="225" class="small muted">订阅 · 每月 23 日</text><text x="350" y="208" text-anchor="end" class="h3">USD 200</text>
{card(20,264,350,82)}<text x="38" y="294" class="body">房租</text><text x="38" y="319" class="small muted">还款 · 每月 1 日</text><text x="350" y="302" text-anchor="end" class="h3">USD 1,850</text>
<text x="24" y="396" class="h2">月度预算</text><text x="366" y="396" text-anchor="end" class="body blue">新增预算</text><text x="24" y="422" class="small muted">只统计同币种实际支出。</text>
{card(20,442,350,104)}<text x="38" y="472" class="body">餐饮</text><text x="350" y="472" text-anchor="end" class="body">USD 600</text><rect x="38" y="490" width="304" height="8" rx="4" fill="#E7E9ED"/><rect x="38" y="490" width="176" height="8" rx="4" fill="#1467E8"/><text x="38" y="523" class="small muted">已花 347 · 剩余 253</text>
''')

pages["more-plugins.svg"] = svg("更多插件", f'''
<text x="24" y="78" class="title">更多插件</text>
<text x="24" y="120" class="label muted">导航</text>{card(20,138,350,62)}<text x="42" y="176" class="body">☷　编辑底部导航</text><text x="350" y="176" text-anchor="end" class="h2 muted">›</text>
<text x="24" y="244" class="label muted">已启用</text>
{card(20,262,350,70)}<text x="42" y="292" class="body">我的资料</text><text x="42" y="314" class="small muted">点按打开，不会自动加入底栏</text><text x="350" y="301" text-anchor="end" class="h2 muted">›</text>
{card(20,344,350,70)}<text x="42" y="374" class="body">理账计划</text><text x="42" y="396" class="small muted">点按打开，不会自动加入底栏</text><text x="350" y="383" text-anchor="end" class="h2 muted">›</text>
<text x="24" y="462" class="label muted">已放到底栏</text>
{card(20,480,350,112)}<text x="42" y="514" class="body">助手　　今天　　任务　　随手记</text><text x="42" y="548" class="body">更多插件</text><text x="42" y="574" class="small muted">共 5 个入口</text>
{card(20,624,350,62)}<text x="42" y="662" class="body">🧩　功能与插件设置</text><text x="350" y="662" text-anchor="end" class="h2 muted">›</text>
{bottom_nav("更多插件")}
''')

for filename, content in pages.items():
    (OUT / filename).write_text(content, encoding="utf-8")

print(f"generated {len(pages)} assets in {OUT}")
