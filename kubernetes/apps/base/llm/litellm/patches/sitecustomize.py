"""Randomise least-busy tie-breaks in LiteLLM 1.110.2.

Upstream picks the first deployment on a tie:

    def _least_busy_index(counts):
        return min(range(len(counts)), key=lambda index: counts[index])

With two idle deployments that is always the first one, so sequential traffic
all lands on the same engine and the peer only receives work once the first is
saturated. This shim replaces the function with a uniform choice among the tied
deployments, which is what "least busy" is meant to mean.

The function is only called from inside litellm/router_strategy/least_busy.py,
where the module global is resolved at call time, so patching the module
attribute is enough. Delete this file once the fix ships upstream.
"""

import builtins
import random
import sys

_TARGET = "litellm.router_strategy.least_busy"
_installed = False


def _least_busy_index(counts):
    lowest = min(counts)
    tied = [index for index, count in enumerate(counts) if count == lowest]
    return random.choice(tied) if len(tied) > 1 else tied[0]


def _install():
    global _installed
    if _installed:
        return
    module = sys.modules.get(_TARGET)
    if module is None:
        return
    module._least_busy_index = _least_busy_index
    _installed = True


_real_import = builtins.__import__


def _import(name, globals=None, locals=None, fromlist=(), level=0):
    module = _real_import(name, globals, locals, fromlist, level)
    if not _installed and name.split(".")[0] == "litellm":
        _install()
    return module


builtins.__import__ = _import
