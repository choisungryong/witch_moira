"""Subprocess helper for the balance lab: asks tools/dev/balance_sim.py what it knows, prints one JSON document.

Run by balance_lab.py with `python -I`; the simulator is only imported here, never inside the manager server.
Usage: balance_lab_probe.py <repo-root> [<preset> <spells-file>]
Every lookup is optional: a missing attribute yields null so a changed simulator cannot crash the lab.
"""
import argparse, importlib.util, json, sys
from pathlib import Path


def main():
    root = Path(sys.argv[1]).resolve()
    preset = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
    spells = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
    path = root / 'tools' / 'dev' / 'balance_sim.py'
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location('balance_sim_probe_target', path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    out = {'ok': True}

    def get(name, default=None):
        return getattr(mod, name, default)

    def jsonable(v):
        return json.loads(json.dumps(v, ensure_ascii=False, default=lambda o: list(o) if isinstance(o, (set, tuple)) else str(o)))

    try:
        mode = (get('default_policies') or (lambda m: []))('s')
    except Exception:
        mode = []
    out['policies'] = list(mode)
    out['pair_roles'] = jsonable(get('PAIR_ROLES', []))
    out['witches'] = jsonable(list(get('ELEMS', ('ember', 'frost', 'arc'))))
    out['p7'] = jsonable(get('P7_WIN', {}))
    out['p4'] = jsonable(get('P4_R', {}))
    cfg_info = {}
    try:
        ns = argparse.Namespace(spells=spells, preset=None, skills=None, dt=1.0, gear=None)
        cfg = mod.load_cfg(ns, sets=[], preset=preset)
        cfg_info['rhythm'] = jsonable(cfg.tuning.get('rhythm', {}))
        cfg_info['seal_kills'] = jsonable(cfg.tuning.get('seal_kills'))
        cfg_info['spells'] = jsonable(cfg.spells)
        cfg_info['spells_path'] = str(cfg.spells_path)
        cfg_info['mode'] = cfg.mode
        cfg_info['calib'] = jsonable({k: {'value': v.get('value'), 'source': v.get('source'), 'note': v.get('note')}
                                      for k, v in cfg.calib_doc.get('params', {}).items()})
        cfg_info['calib_current'] = jsonable(cfg.cal)
    except SystemExit as e:
        out['config_error'] = 'SystemExit: %s' % (e,)
    except Exception as e:
        out['config_error'] = '%s: %s' % (e.__class__.__name__, e)
    out['config'] = cfg_info
    sys.stdout.reconfigure(encoding='utf-8')
    print(json.dumps(out, ensure_ascii=False))


if __name__ == '__main__':
    main()
