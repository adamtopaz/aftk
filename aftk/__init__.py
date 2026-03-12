"""Top-level Python package for AFTK.

This package currently re-exports the existing toolkit-facing client API from
``aftk_client`` while the broader Python surface is harmonized under ``aftk``.
"""

import logging

import aftk_client as _aftk_client
from aftk_client import *  # noqa: F401,F403


logging.getLogger("aftk").addHandler(logging.NullHandler())


__all__ = list(_aftk_client.__all__)
