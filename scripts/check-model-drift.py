#!/usr/bin/env python3
"""Compara modelos SQLAlchemy del schema mapalab.* entre mapalab y mariachi.

Uso:
    python scripts/check-model-drift.py
    python scripts/check-model-drift.py --mapalab /ruta --mariachi /ruta

Exit 0 si estan alineados, 1 si hay drift. Pensado para correrse manualmente
o en CI de cualquiera de los repos que toca mapalab.*.
"""
from __future__ import annotations

import argparse
import ast
import sys
from pathlib import Path


DEFAULT_MAPALAB = Path('/home/egar/IIEG/mapalab/backend/app/models')
DEFAULT_MARIACHI = Path('/home/egar/IIEG/mariachi/api/app/models')

SHARED_TABLES = {'workspaces', 'layers', 'initial_layer_order', 'layer_metadata', 'layer_stats'}


def _arg_to_str(node: ast.AST) -> str:
    if isinstance(node, ast.Constant):
        return repr(node.value)
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return f'{_arg_to_str(node.value)}.{node.attr}'
    if isinstance(node, ast.Call):
        func = _arg_to_str(node.func)
        args = ', '.join(_arg_to_str(a) for a in node.args)
        kwargs = ', '.join(f'{k.arg}={_arg_to_str(k.value)}' for k in node.keywords if k.arg)
        parts = ', '.join(p for p in (args, kwargs) if p)
        return f'{func}({parts})'
    if isinstance(node, ast.Tuple):
        return '(' + ', '.join(_arg_to_str(e) for e in node.elts) + ')'
    return ast.unparse(node) if hasattr(ast, 'unparse') else '<?>'


def _extract_tablename(class_node: ast.ClassDef) -> str | None:
    for stmt in class_node.body:
        if isinstance(stmt, ast.Assign):
            for t in stmt.targets:
                if isinstance(t, ast.Name) and t.id == '__tablename__':
                    if isinstance(stmt.value, ast.Constant):
                        return stmt.value.value
    return None


def _extract_columns(class_node: ast.ClassDef) -> dict[str, str]:
    cols: dict[str, str] = {}
    for stmt in class_node.body:
        if isinstance(stmt, ast.Assign) and len(stmt.targets) == 1:
            target = stmt.targets[0]
            if isinstance(target, ast.Name) and isinstance(stmt.value, ast.Call):
                func = _arg_to_str(stmt.value.func)
                if func.endswith('Column'):
                    cols[target.id] = _arg_to_str(stmt.value)
    return cols


def parse_models(models_dir: Path) -> dict[str, dict[str, str]]:
    """Retorna {tablename: {col_name: col_signature}} para tablas del schema mapalab."""
    tables: dict[str, dict[str, str]] = {}
    for py_file in models_dir.glob('*.py'):
        if py_file.name.startswith('__'):
            continue
        tree = ast.parse(py_file.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef):
                tablename = _extract_tablename(node)
                if tablename in SHARED_TABLES:
                    tables[tablename] = _extract_columns(node)
    return tables


def compare(a: dict[str, dict[str, str]], b: dict[str, dict[str, str]], label_a: str, label_b: str) -> list[str]:
    diffs: list[str] = []
    for table in SHARED_TABLES:
        cols_a = a.get(table)
        cols_b = b.get(table)
        if cols_a is None and cols_b is None:
            continue
        if cols_a is None:
            diffs.append(f'[{table}] definida en {label_b} pero no en {label_a}')
            continue
        if cols_b is None:
            diffs.append(f'[{table}] definida en {label_a} pero no en {label_b}')
            continue

        only_a = set(cols_a) - set(cols_b)
        only_b = set(cols_b) - set(cols_a)
        for c in sorted(only_a):
            diffs.append(f'[{table}] columna "{c}" solo en {label_a}')
        for c in sorted(only_b):
            diffs.append(f'[{table}] columna "{c}" solo en {label_b}')

        for c in sorted(set(cols_a) & set(cols_b)):
            if cols_a[c] != cols_b[c]:
                diffs.append(f'[{table}] columna "{c}" difiere:\n  {label_a}: {cols_a[c]}\n  {label_b}: {cols_b[c]}')
    return diffs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--mapalab', type=Path, default=DEFAULT_MAPALAB)
    ap.add_argument('--mariachi', type=Path, default=DEFAULT_MARIACHI)
    args = ap.parse_args()

    if not args.mapalab.is_dir():
        print(f'ERROR: no existe {args.mapalab}', file=sys.stderr)
        return 2
    if not args.mariachi.is_dir():
        print(f'ERROR: no existe {args.mariachi}', file=sys.stderr)
        return 2

    ma = parse_models(args.mapalab)
    mi = parse_models(args.mariachi)

    print(f'mapalab:  {len(ma)} tabla(s) del schema mapalab.* detectada(s)')
    print(f'mariachi: {len(mi)} tabla(s) del schema mapalab.* detectada(s)')
    print()

    diffs = compare(ma, mi, 'mapalab', 'mariachi')

    if not diffs:
        print('OK: modelos alineados.')
        return 0

    print(f'DRIFT detectado ({len(diffs)} diferencia(s)):')
    for d in diffs:
        print(f'  - {d}')
    return 1


if __name__ == '__main__':
    sys.exit(main())
