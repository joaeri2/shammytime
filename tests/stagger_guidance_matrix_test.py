#!/usr/bin/env python3
"""Thin wrapper to run the canonical stagger guidance matrix script.

Canonical implementation lives in:
- Helpers/stagger_guidance_matrix.py
"""

import os
import sys


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    helpers = os.path.join(root, "Helpers")
    if helpers not in sys.path:
        sys.path.insert(0, helpers)

    from stagger_guidance_matrix import run  # pylint: disable=import-error

    return run()


if __name__ == "__main__":
    raise SystemExit(main())
