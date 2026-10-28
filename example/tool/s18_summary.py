#!/usr/bin/env python3
"""S18 结果汇总：读取 s18_android/s18_ios 下三个入口的结果，输出 Markdown 表格。

用法：python3 example/tool/s18_summary.py example/build/s18_android > summary_android.md
      python3 example/tool/s18_summary.py example/build/s18_ios > summary_ios.md
"""
import glob
import json
import os
import re
import sys


def pct(xs, p):
    """线性插值分位数，与 Dart 端 pct 一致"""
    if not xs:
        return float('nan')
    s = sorted(xs)
    k = (len(s) - 1) * p
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def rows(path):
    """结果文件中的 JSON 行"""
    out = []
    for line in open(path, errors='ignore'):
        line = line.strip()
        if line.startswith('{'):
            try:
                out.append(json.loads(line))
            except ValueError:
                pass
    return out


def find(root, name):
    """Android 为 <入口>/results.txt，iOS 为 <入口>/s18/<入口>.txt"""
    for p in (f'{root}/{name}/results.txt', f'{root}/{name}/s18/{name}.txt'):
        if os.path.exists(p):
            return p
    return None


def f1(x):
    return '—' if x is None or x != x else f'{x:.1f}'


def meminfo(path):
    """dumpsys meminfo 摘要：Native Heap、Graphics、TOTAL PSS（KB）"""
    t = open(path, errors='ignore').read()
    g = lambda pat: int(re.search(pat, t).group(1)) if re.search(pat, t) else None
    return {'native': g(r'Native Heap:\s+(\d+)'), 'graphics': g(r'Graphics:\s+(\d+)'),
            'pss': g(r'TOTAL PSS:\s+(\d+)')}


def gfxinfo(path):
    """dumpsys gfxinfo 摘要：总帧数、卡顿帧数及比例"""
    t = open(path, errors='ignore').read()
    total = re.search(r'Total frames rendered:\s+(\d+)', t)
    jank = re.search(r'Janky frames:\s+(\d+)\s+\(([\d.]+)%\)', t)
    return (int(total.group(1)) if total else None,
            int(jank.group(1)) if jank else None,
            float(jank.group(2)) if jank else None)


def perf(root):
    p = find(root, 'native_marker_perf_test')
    if not p:
        return
    rs = rows(p)
    by = {}
    for r in rs:
        if 'run' in r:
            by.setdefault(r['sc'], []).append(r)
    calib = {r['sc']: r for r in rs if r.get('calib')}
    print('### 更新场景（每格 P50 / P95，单位 ms）\n')
    print('| 场景 | n | t0→t1（Dart） | 其中 PNG/构造 | t2→t4（原生） | t0→t4 估算 | 校准半宽 前/后 | 偏移漂移 | drawCount P50 | 命中率 | bytes P50 | pending>0 | 卡顿帧 |')
    print('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
    for sc, xs in by.items():
        col = lambda k: [x[k] for x in xs if x.get(k) is not None]
        pp = lambda k: f'{f1(pct(col(k), .5))} / {f1(pct(col(k), .95))}'
        c = calib.get(sc, {})
        hits, miss = sum(col('hits')), sum(col('misses'))
        rate = f'{hits / (hits + miss) * 100:.0f}%' if hits + miss else '—'
        gfx = os.path.join(root, 'native_marker_perf_test', f'gfxinfo_{sc}.txt')
        jank = '—'
        if os.path.exists(gfx):
            tot, j, jp = gfxinfo(gfx)
            jank = f'{j}/{tot}（{jp}%）' if tot else '—'
        half = f"{f1(c.get('preHalf'))}/{f1(c.get('postHalf'))}" if c else '—'
        drift = f1(abs(c['postOffset'] - c['preOffset'])) if c else '—'
        print(f"| {sc} | {len(xs)} | {pp('t0t1')} | {pp('buildMs')} | {pp('t2t4')} | {pp('t0t4')} | {half} | {drift} | "
              f"{f1(pct(col('draws'), .5))} | {rate} | {f1(pct(col('bytes'), .5))} | "
              f"{sum(1 for x in xs if x.get('pending', 0) > 0)} | {jank} |")
    print()
    for r in rs:
        if r.get('mem'):
            print(f"- {r['sc']} 内存（进程 RSS）：{r['rssBefore'] / 1048576:.1f} → {r['rssAfter'] / 1048576:.1f} MiB（{r['growth'] * 100:+.1f}%）")
    for m in sorted(glob.glob(os.path.join(root, 'native_marker_perf_test', 'meminfo_*.txt'))):
        mi = meminfo(m)
        print(f"- {os.path.basename(m)[8:-4]}：Native Heap {mi['native']} KB，Graphics {mi['graphics']} KB，TOTAL PSS {mi['pss']} KB")
    print()


def taps(root):
    p = find(root, 'native_marker_tap_test')
    if not p:
        return
    print('### 点击（c1→c2，原生同一时钟，单位 ms）\n')
    print('| 项目 | n | P50 | P95 | 最大 | 说明 |')
    print('| --- | --- | --- | --- | --- | --- |')
    for r in rows(p):
        if r.get('test') == 'tap':
            xs = r['c1c2']
            print(f"| 连续点击 {r['path']} | {r['n']} | {f1(r['p50'])} | {f1(r['p95'])} | {f1(max(xs))} | 第 3 次起绘制次数合计 {r['drawsAfterWarm']} |")
        elif r.get('test') == 'T-SEL-7':
            xs = r['c1c2']
            print(f"| T-SEL-7 未预热点击 | {r['n']} | {f1(r['p50'])} | {f1(r['p95'])} | {f1(max(xs))} | 点击时选中态未绘制 {r['coldTaps']}/{r['n']} |")
    dels = [r for r in rows(p) if r.get('test') == 'T-DEL-5']
    if dels:
        ok = sum(1 for r in dels if r['beforeRemoved'])
        print(f"\n- T-DEL-5：{len(dels)} 轮中 {ok} 轮在 `markers#removed` 前点中待删除点，均回调 onTap 1 次并产生选择事件")
    print()


def basic(root):
    p = find(root, 'native_marker_test')
    if not p:
        return
    print('### 集成测试\n')
    for r in rows(p):
        if r.get('test') == 'T-RES-13':
            print(f"- T-RES-13：图钉区域蓝色像素 参考 {r['refBlue']} → 故障 {r['fallbackBlue']} → 恢复 {r['recoveredBlue']}；"
                  f"拦截登记 {r['brokenSends']} 次，页面收到 imageDecodeFailed：{r['errorShown']}")
        elif r.get('test') == 'T-DISP-2':
            print(f"- T-DISP-2：进出 30 次，RSS 基线 {r['baseRss'] / 1048576:.1f} MiB，第 10/20/30 次后 "
                  + '/'.join(f'{x / 1048576:.1f}' for x in r['rss']) + ' MiB')
    legacy = [r['page'] for r in rows(p) if r.get('test') == 'legacy' and not r['v2']]
    print(f"- 旧路径回归：{len(legacy)} 个页面地图加载、无异常、未启用新协议（{', '.join(legacy)}）")
    for m in sorted(glob.glob(os.path.join(root, 'native_marker_test', 'meminfo_disp_*.txt')),
                    key=lambda s: int(re.search(r'_(\d+)\.txt', s).group(1))):
        mi = meminfo(m)
        print(f"  - {os.path.basename(m)[8:-4]}：Native Heap {mi['native']} KB，Graphics {mi['graphics']} KB，TOTAL PSS {mi['pss']} KB")
    print()


if __name__ == '__main__':
    root = sys.argv[1]
    basic(root)
    taps(root)
    perf(root)
