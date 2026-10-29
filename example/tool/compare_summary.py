#!/usr/bin/env python3
"""AM-P02 对照测试汇总：把一个平台的原始结果转成报告用的 Markdown 表格。

用法：python3 example/tool/compare_summary.py <结果文件或目录>...
  文件：marker_compare_test 输出的结果（JSON 行）。
  目录：读其中的 results.txt / s18/*.txt，以及 meminfo_mem_*.txt（Android 内存）。
例：python3 example/tool/compare_summary.py build/compare_60hz_BRE-AL80/{push.txt,tap.txt,mem_native,mem_png}
"""
import glob
import json
import os
import re
import sys

LOAD = {'push_off': '无', 'push_heavy': '重', 'pan_heavy': '平移+重'}
SCHEME = {'native': '原生', 'png': 'PNG', 'icon': 'PNG'}


def pct(xs, p):
    """线性插值分位数，与 Dart 端 pct 一致"""
    if not xs:
        return float('nan')
    s = sorted(xs)
    k = (len(s) - 1) * p
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def f(x, d=1):
    return '—' if x is None or x != x else f'{x:.{d}f}'


def pp(xs, d=1):
    """P50 / P95"""
    return f'{f(pct(xs, .5), d)} / {f(pct(xs, .95), d)}'


def size(kb):
    return f'{kb:.0f}KB' if kb < 1024 else f'{kb / 1024:.1f}MB'


def load(paths):
    """收集 JSON 行与 meminfo 文件"""
    rows, mems = [], []
    for p in paths:
        files = [p]
        if os.path.isdir(p):
            files = glob.glob(f'{p}/results.txt') + glob.glob(f'{p}/s18/*.txt')
            mems += glob.glob(f'{p}/meminfo_mem_*.txt')
        for fn in files:
            for line in open(fn, errors='ignore'):
                if line.startswith('{'):
                    try:
                        rows.append(json.loads(line))
                    except ValueError:
                        pass
    return rows, mems


def push(rows):
    rs = [r for r in rows if 'run' in r and r.get('sc', '').startswith(('push', 'pan'))]
    keys = sorted({(r['n'], r['sc'], r['scheme']) for r in rs},
                  key=lambda k: (k[0], list(LOAD).index(k[1]) if k[1] in LOAD else 9, k[2]))
    g = lambda k: [r for r in rs if (r['n'], r['sc'], r['scheme']) == k]
    col = lambda xs, c: [x[c] for x in xs if x.get(c) is not None]
    print('### 推送新价格（P50 / P95，毫秒）\n')
    print('| 点数 | 负载 | 方案 | 轮数 | Dart 构造 | 到达→发送 t0→t1 | 原生应用 t2→t4 | 到达→应用 t0→t4 | 传输 P50 | 绘制次数 P50 |')
    print('|---|---|---|---|---|---|---|---|---|---|')
    for k in keys:
        xs = g(k)
        print(f"| {k[0]} | {LOAD.get(k[1], k[1])} | {SCHEME[k[2]]} | {len(xs)} | {pp(col(xs, 'buildMs'))} | "
              f"{pp(col(xs, 't0t1'), 0)} | {pp(col(xs, 't2t4'), 0)} | **{pp(col(xs, 't0t4'), 0)}** | "
              f"{size(pct(col(xs, 'bytes'), .5) / 1024) if pct(col(xs, 'bytes'), .5) else '0'} | "
              f"{f(pct(col(xs, 'draws'), .5), 0)} |")
    print('\n### 推送期间 Flutter 帧（窗口：推送开始 → 回执后 1 秒）\n')
    print('| 点数 | 负载 | 方案 | 窗口时长 P50 | 窗口帧数 P50 | 卡顿帧合计（构建 / 绘制） | 卡顿帧 P50 / P95 | 丢帧 P50 / P95（合计） | 丢帧率 | 单帧最长 P50 / P95 |')
    print('|---|---|---|---|---|---|---|---|---|---|')
    for k in keys:
        xs = g(k)
        jb, jr = sum(col(xs, 'jankBuild')), sum(col(xs, 'jankRaster'))
        jank = [x.get('jankBuild', 0) + x.get('jankRaster', 0) for x in xs]
        dr, fr = col(xs, 'dropped'), col(xs, 'frames')
        drop = f'{pp(dr, 0)}（{sum(dr)}）' if dr else '—'
        # 丢帧率 = 丢帧 ÷ 应有帧数（实际帧 + 丢帧），窗口长短不同时也能比
        rate = f'{100 * sum(dr) / (sum(dr) + sum(fr)):.0f}%' if dr and fr else '—'
        win = col(xs, 'windowMs')
        print(f"| {k[0]} | {LOAD.get(k[1], k[1])} | {SCHEME[k[2]]} | {f(pct(win, .5) / 1000, 1) + 's' if win else '—'} | "
              f"{f(pct(fr, .5), 0)} | {jb + jr}（{jb} / {jr}） | {pp(jank, 1)} | {drop} | {rate} | {pp(col(xs, 'worstMs'))}ms |")
    print()
    # 发热状态（iOS 0～3：2=serious；Android 0～6：2=moderate）：每组列出各取值的轮数
    th = [r for r in rs if r.get('thermal') is not None]
    if th:
        print('发热状态（取值：轮数）：' + '；'.join(
            f"{k[0]} 点 {LOAD.get(k[1], k[1])} {SCHEME[k[2]]} "
            + '、'.join(f'{v}:{c}' for v, c in sorted(__import__('collections').Counter(
                x['thermal'] for x in th if (x['n'], x['sc'], x['scheme']) == k).items()))
            for k in keys) + '\n')
    else:
        print('发热状态：未记录\n')
    return keys


def tap(rows):
    rs = [r for r in rows if r.get('sc') == 'tap' and 'c1c2' in r and not r.get('summary')]
    if not rs:
        return False
    print('### 点击选中（c1→c2，毫秒）\n')
    print('| 方案 | 样本 | P50 | P95 | 最小 / 最大 | 点击期间绘制 |')
    print('|---|---|---|---|---|---|')
    for s in ('native', 'png'):
        xs = [r for r in rs if r['scheme'] == s]
        if not xs:
            continue
        c = [x['c1c2'] for x in xs]
        d = [x.get('draws', 0) for x in xs]
        dist = '全部为 0' if not any(d) else '，'.join(f'{d.count(v)} 次为 {v}' for v in sorted(set(d)))
        print(f'| {SCHEME[s]} | {len(xs)} | {f(pct(c, .5))} | {f(pct(c, .95))} | {f(min(c))} / {f(max(c))} | {dist} |')
    print()
    return True


def meminfo(path):
    """App Summary 段：Native Heap、Java Heap、TOTAL PSS（MB，KB/1024 取整）"""
    t = open(path, errors='ignore').read()
    g = lambda pat: round(int(re.search(pat, t).group(1)) / 1024) if re.search(pat, t) else None
    return g(r'\n\s+Native Heap:\s+(\d+)'), g(r'\n\s+Java Heap:\s+(\d+)'), g(r'TOTAL PSS:\s+(\d+)')


def mem(rows, mems):
    rs = [r for r in rows if r.get('sc') == 'mem' and r.get('summary')]
    if not rs:
        return False
    info = {re.search(r'meminfo_mem_(.+)\.txt', m).group(1): meminfo(m) for m in mems}
    print('### 内存（MB）\n')
    if info:
        print('| 方案 | 点数 | 时刻 | TOTAL PSS | Native Heap | Java Heap | 进程 RSS（Dart 读取） |')
        print('|---|---|---|---|---|---|---|')
    else:
        print('| 方案 | 点数 | 批数 | RSS 基线 | RSS 峰值 | RSS 清空后 |')
        print('|---|---|---|---|---|---|')
    for r in sorted(rs, key=lambda r: (r['n'], r['scheme'] != 'native')):
        if not info:
            print(f"| {SCHEME[r['scheme']]} | {r['n']} | {r['rounds']} | {r['rssBaseMB']:.0f} | {r['rssPeakMB']:.0f} | {r['rssEndMB']:.0f} |")
            continue
        for tag, name, rss in (('base', '基线', 'rssBaseMB'), ('peak', '峰值', 'rssPeakMB'), ('end', '清空后', 'rssEndMB')):
            nat, java, pss = info.get(f"{r['scheme']}_{r['n']}_{tag}", (None,) * 3)
            print(f"| {SCHEME[r['scheme']]} | {r['n']} | {name} | {pss or '—'} | {nat or '—'} | {java or '—'} | {r[rss]:.0f} |")
        nat, java, pss = info.get(f"{r['scheme']}_{r['n']}_cycle", (None,) * 3)
        if pss:
            print(f"| {SCHEME[r['scheme']]} | {r['n']} | 再循环 4 次后 | {pss} | {nat} | {java} | {r['rssCyclesMB'][-1]:.0f} |")
    print()
    cy = [r for r in rs if r.get('rssCyclesMB')]
    if cy:
        print('每次清空后 RSS（MB，第 1 次为上表“清空后”，之后每次先推送 2 批再清空）：\n')
        for r in sorted(cy, key=lambda r: (r['n'], r['scheme'] != 'native')):
            v = r['rssCyclesMB']
            print(f"- {SCHEME[r['scheme']]} {r['n']} 点：{' → '.join(f'{x:.0f}' for x in v)}（首末差 {v[-1] - v[0]:+.0f}）")
        print()
    return True


if __name__ == '__main__':
    rows, mems = load(sys.argv[1:])
    dev = next((r for r in rows if 'device' in r), {})
    print(f"设备：{dev.get('device', '?')}，dpr {dev.get('dpr', '?')}，刷新率 {f(dev.get('refreshRate'), 0)}Hz\n")
    keys = push(rows)
    has_tap, has_mem = tap(rows), mem(rows, mems)
    # 数据完整性：缺项或某方案缺组时提示
    warn = [] if keys else ['没有推送数据']
    groups = {(n, sc) for n, sc, _ in keys}
    warn += [f'{n} 点 {sc} 只有一种方案' for n, sc in groups if sum(1 for k in keys if k[:2] == (n, sc)) < 2]
    warn += [] if has_tap else ['没有点击数据']
    warn += [] if has_mem else ['没有内存数据']
    print('### 数据检查\n')
    print('\n'.join(f'- {w}' for w in warn) if warn else '- 推送、点击、内存数据齐全')
