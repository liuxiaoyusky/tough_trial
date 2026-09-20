#!/usr/bin/env python3
"""Read-only business/source map. Compiler parse ranges, curated edges; not a resolved call graph."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
GRAPH = Path('ontology/task-workspace.json')
SCHEMA = Path('ontology/schema.json')
INDEX = Path('.build/ontology/task-workspace.index.json')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(root, value):
    path = (root / value).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f'路径越出仓库: {value}')
    if not path.is_file():
        raise ValueError(f'文件不存在: {value}')
    return path


def declarations(dump):
    """Extract named declarations/accessors from this toolchain's -dump-parse output.
    Scopes and positions come from the compiler. No calls are inferred from text matches.
    """
    scopes, result = [], []
    for line in dump.splitlines():
        kind = re.match(r'\s*\((\w+_decl)\b', line)
        if not kind:
            continue
        span = re.search(r'range=\[.*?:(\d+):(\d+) - (?:line:)?(\d+):(\d+)\]', line)
        if not span:
            continue
        name = re.search(r'"([^"\n]+)"', line[span.end():])
        if not name:
            continue
        kind, name = kind.group(1), name.group(1)
        start, _, end, _ = map(int, span.groups())
        while scopes and not (scopes[-1][0] <= start <= end <= scopes[-1][1]):
            scopes.pop()
        owners = [item[2] for item in scopes]
        symbol = '.'.join(owners + [name])
        if kind in ('struct_decl', 'class_decl', 'enum_decl', 'extension_decl', 'protocol_decl'):
            result.append({'symbol': symbol, 'kind': kind, 'range': list(map(int, span.groups()))})
            scopes.append((start, end, name))
        elif kind in ('func_decl', 'constructor_decl', 'accessor_decl', 'var_decl'):
            # Getter and setter need distinct IDs. A property selector is bound to its getter.
            if kind == 'accessor_decl':
                if not re.search(r'\bget for=', line):
                    continue
                symbol += '.get'
            result.append({'symbol': symbol, 'kind': kind, 'range': list(map(int, span.groups()))})
    return result


def validate(graph, schema, root):
    try:
        from jsonschema import Draft202012Validator
    except ImportError as exc:
        raise ValueError('需要 jsonschema>=4；按 Tools/OntologyIndexer/README.md 配置开发环境') from exc
    errors = list(Draft202012Validator(schema).iter_errors(graph))
    if errors:
        raise ValueError('Ontology 格式错误: ' + errors[0].message)
    nodes = graph['nodes']
    ids = [n['id'] for n in nodes]
    if len(set(ids)) != len(ids):
        raise ValueError('节点 ID 重复')
    types = {n['id']: n['type'] for n in nodes}
    for node in nodes:
        if node['type'] in ('symbol', 'test') and 'binding' not in node:
            raise ValueError(f"代码节点缺少绑定: {node['id']}")
        if 'binding' in node:
            safe_path(root, node['binding']['path'])
        for reference in node.get('references', []):
            safe_path(root, reference)
    for edge in graph['edges']:
        if edge['from'] not in types or edge['to'] not in types:
            raise ValueError(f'关系引用不存在的节点: {edge}')
        if edge['relation'] == 'verified_by' and types[edge['to']] != 'test':
            raise ValueError('verified_by 必须指向测试用例')
        if edge['relation'] == 'writes' and types[edge['to']] != 'data':
            raise ValueError('writes 必须指向数据节点')
        if edge['relation'] == 'constrained_by' and types[edge['to']] != 'invariant':
            raise ValueError('constrained_by 必须指向业务规则')
        safe_path(root, edge['evidence'])


def build(root=ROOT, graph_path=GRAPH, index_path=INDEX):
    graph = json.loads(safe_path(root, graph_path).read_text())
    schema = json.loads(safe_path(root, SCHEMA).read_text())
    validate(graph, schema, root)
    hashes, parsed = {}, {}
    paths = {str(graph_path), str(SCHEMA), 'Tools/OntologyIndexer/ontology.py'}
    for node in graph['nodes']:
        paths.update(node.get('references', []))
        if 'binding' in node:
            paths.add(node['binding']['path'])
    paths.update(e['evidence'] for e in graph['edges'])
    for path in sorted(paths):
        hashes[path] = digest(safe_path(root, path).read_bytes())
    for node in graph['nodes']:
        binding = node.get('binding')
        if not binding:
            continue
        path = binding['path']
        if path not in parsed:
            process = subprocess.run(['xcrun', 'swiftc', '-frontend', '-dump-parse', path], cwd=root,
                                     capture_output=True, text=True, timeout=60)
            if process.returncode:
                raise ValueError(f'Swift 解析失败: {path}\n{process.stderr[:1500]}')
            parsed[path] = declarations(process.stdout)
        matches = [d for d in parsed[path] if d['symbol'] == binding['symbol']]
        if len(matches) != 1:
            raise ValueError(f"绑定须唯一解析，实际 {len(matches)} 个: {node['id']} → {binding}")
        node['location'] = {**matches[0], 'path': path, 'sourceHash': hashes[path], 'evidence': 'compiler_parse'}
    # Refuse to publish a mixed-version index if files changed while parsing.
    for path, expected in hashes.items():
        if digest(safe_path(root, path).read_bytes()) != expected:
            raise ValueError(f'索引期间源码变化，请重试: {path}')
    commit = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=root, capture_output=True, text=True, check=True).stdout.strip()
    version = subprocess.run(['xcrun', 'swiftc', '--version'], capture_output=True, text=True, check=True).stdout.strip()
    index = {'formatVersion': 1, 'commit': commit, 'sourceFingerprint': digest(json.dumps(hashes, sort_keys=True).encode()),
             'toolchain': version, 'coverage': 'curated task workspace; syntax declarations only; no runtime evidence',
             'files': hashes, 'graph': graph}
    output = root / index_path
    output.parent.mkdir(parents=True, exist_ok=True)
    staged = output.with_suffix('.tmp')
    staged.write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n')
    staged.replace(output)
    return index


def load_current(root=ROOT, index_path=INDEX):
    index = json.loads(safe_path(root, index_path).read_text())
    if index.get('formatVersion') != 1:
        raise ValueError('不支持的索引版本，请重建')
    for path, expected in index['files'].items():
        if digest(safe_path(root, path).read_bytes()) != expected:
            raise ValueError(f'索引已过期: {path}。请执行 ontology.py build；拒绝返回旧行号。')
    return index


def query(index, text, limit=32):
    graph = index['graph']
    matches = [n for n in graph['nodes'] if text.casefold() in ' '.join(
        [n['id'], n['label']] + n.get('aliases', [])).casefold()]
    selected = {n['id'] for n in matches}
    # Four bounded hops expose input, commands, persistence and tests without dumping the repository.
    for _ in range(4):
        adjacent = {e['to'] if e['from'] in selected else e['from'] for e in graph['edges']
                    if e['from'] in selected or e['to'] in selected}
        selected.update(sorted(adjacent)[:limit])
    nodes = sorted((n for n in graph['nodes'] if n['id'] in selected), key=lambda n: (n not in matches, n['id']))[:limit]
    ids = {n['id'] for n in nodes}
    return {'query': text, 'matches': [n['id'] for n in matches], 'sourceFingerprint': index['sourceFingerprint'],
            'scope': index['coverage'], 'nodes': nodes,
            'edges': [e for e in graph['edges'] if e['from'] in ids and e['to'] in ids],
            'truncated': len(selected) > len(nodes),
            'diagnosis': '仅提供已纳管静态候选与来源；没有运行 trace 时不判断根因或概率。'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('build')
    sub.add_parser('check')
    find = sub.add_parser('query')
    find.add_argument('text')
    args = parser.parse_args()
    try:
        if args.command == 'build':
            index = build()
            print(json.dumps({'status': 'built', 'nodes': len(index['graph']['nodes']), 'edges': len(index['graph']['edges']),
                              'index': str(INDEX)}, ensure_ascii=False))
        else:
            index = load_current()
            print(json.dumps(query(index, args.text) if args.command == 'query' else
                             {'status': 'current', 'sourceFingerprint': index['sourceFingerprint']}, ensure_ascii=False, indent=2))
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
