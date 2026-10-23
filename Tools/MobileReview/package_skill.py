#!/usr/bin/env python3
"""Refresh the self-contained skill payload from the canonical CLI and web assets."""
from pathlib import Path
import shutil

source = Path(__file__).resolve().parent
skill = source.parents[1] / 'skills/mobile-review'
payload = skill / 'scripts'
payload.mkdir(parents=True, exist_ok=True)
shutil.copyfile(source / 'cli.py', payload / 'mobile-review.py')
(payload / 'mobile-review.py').chmod(0o755)
shutil.copytree(source / 'web', payload / 'web', dirs_exist_ok=True)
print(skill)
