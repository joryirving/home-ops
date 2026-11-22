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
attribute is enough. Delete this file once the fix ships upstream
(BerriAI/litellm#53513).

The import is eager: litellm's own imports do not go through
builtins.__import__, so an import hook never observes them. The cost is about
3.5s once per Python process in this container.
"""

import random


def _least_busy_index(counts):
    lowest = min(counts)
    tied = [index for index, count in enumerate(counts) if count == lowest]
    return random.choice(tied) if len(tied) > 1 else tied[0]


try:
    from litellm.router_strategy import least_busy as _least_busy
except Exception:  # pragma: no cover - never block startup on a shim
    _least_busy = None

if _least_busy is not None:
    _least_busy._least_busy_index = _least_busy_index
