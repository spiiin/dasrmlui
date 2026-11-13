"""Summarize measured CSV; Python standard library only. Times are microseconds."""
import argparse
import csv
import gzip
import math
from collections import defaultdict
from pathlib import Path
from statistics import mean, median

MODES = ['DSL', 'native', 'hybrid']
SCENARIOS = ['idle', 'single', 'bulk', 'rotate']
PHASES = ['bindings', 'update', 'render_cpu', 'gpu_wait', 'gc', 'timer_baseline', 'mutation', 'prepare']
UNCOUNTED = str(2**64 - 1)


def percentile(values, fraction):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * fraction) - 1)]


def analyze(source):
    groups = defaultdict(lambda: {'timing': [], 'memory': []})
    opener = gzip.open if source.suffix == '.gz' else open
    with opener(source, 'rt', newline='') as stream:
        for row in csv.DictReader(stream):
            key = tuple(int(row[k]) for k in ('mode', 'scenario', 'phase'))
            groups[key]['timing' if row['cpp_allocs'] == UNCOUNTED else 'memory'].append(row)
    # Pair each frame's mutation+binding costs. Do not add independently computed medians.
    for (mode, scenario, phase), samples in list(groups.items()):
        if phase != 6:
            continue
        combined = groups[mode, scenario, 7]
        for kind in ('timing', 'memory'):
            bindings = {(r['round'], r['frame']): r for r in groups[mode, scenario, 0][kind]}
            for mutation in samples[kind]:
                binding = bindings[mutation['round'], mutation['frame']]
                row = dict(binding, phase='7', us=str(float(binding['us']) + float(mutation['us'])))
                for field in ('cpp_allocs', 'cpp_bytes', 'das_allocs', 'das_bytes', 'das_live_delta'):
                    row[field] = UNCOUNTED if binding[field] == UNCOUNTED else str(int(binding[field]) + int(mutation[field]))
                combined[kind].append(row)
    present_modes = [m for i, m in enumerate(MODES) if any(k[0] == i for k in groups)]
    output = []
    for (mode, scenario, phase), samples in sorted(groups.items()):
        timing, memory = samples['timing'], samples['memory']
        assert timing and (memory or phase == 5), 'Both timing and memory passes are required'
        values = [float(r['us']) for r in timing]
        assert all(math.isfinite(v) and v >= 0 for v in values)
        rounds = defaultdict(list)
        for row in timing:
            rounds[row['round']].append(float(row['us']))
        round_medians = [median(v) for v in rounds.values()]
        result = dict(engine=MODES[mode], scenario=SCENARIOS[scenario], phase=PHASES[phase],
                      samples=len(timing), median_us=median(values), p95_us=percentile(values, .95),
                      round_min_us=min(round_medians), round_max_us=max(round_medians))
        for key in ('cpp_allocs', 'cpp_bytes', 'das_allocs', 'das_bytes', 'das_live_delta'):
            result[key + '_mean'] = mean(int(r[key]) for r in memory) if memory else 0
        output.append(result)
    assert {(r['engine'], r['scenario'], r['phase']) for r in output} >= {
        (m, s, p) for m in present_modes for s in SCENARIOS for p in PHASES[:5]}
    target = source.with_name(source.name.removesuffix('.gz').removesuffix('.csv') + '-summary.csv')
    with target.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=output[0].keys())
        writer.writeheader()
        writer.writerows(output)
    print(f'\n{source}: median microseconds; allocation means/frame (separate pass)')
    print('engine scenario  bindings   update   render     wait       GC | C++ allocs/bytes | DAS allocs/bytes')
    for scenario in SCENARIOS:
        for engine in present_modes:
            rows = {r['phase']: r for r in output if r['engine'] == engine and r['scenario'] == scenario}
            times = ' '.join(f"{rows[p]['median_us']:8.2f}" for p in PHASES[:5])
            memory = [sum(rows[p][key + '_mean'] for p in PHASES[:3]) for key in
                      ('cpp_allocs', 'cpp_bytes', 'das_allocs', 'das_bytes')]
            print(f'{engine:6} {scenario:8} {times} | {memory[0]:8.1f}/{memory[1]:.0f} | {memory[2]:8.1f}/{memory[3]:.0f}')
    for r in output:
        if r['phase'] in ('mutation', 'prepare'):
            print(f"{r['phase']:8} {r['engine']:6} {r['scenario']:8}: {r['median_us']:.2f} us, C++ {r['cpp_allocs_mean']:.1f}/{r['cpp_bytes_mean']:.0f} B, DAS {r['das_allocs_mean']:.1f}/{r['das_bytes_mean']:.0f} B")
    print(f'Wrote {target}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv', type=Path, nargs='+')
    for file in parser.parse_args().csv:
        analyze(file)
