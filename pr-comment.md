## 🔍 PR Review: OpenClaw 2026.2.26 → 2026.3.1

### ⚠️ BREAKING CHANGES - Action Required

**1. Node Execution Approval Changes**
- Node exec approval payloads now **require** `systemRunPlan`
- `host=node` approval requests without this plan will be **rejected**
- **Impact**: Any existing node workflows that use `system.run` will break

**2. Node Path Resolution Changes**  
- Node `system.run` now pins path-token commands to **canonical executable path** (`realpath`)
- Commands like `tr` must now use `/usr/bin/tr`
- **Impact**: Any scripts/tools that use bare command names will fail

### 🏠 Home-Ops Specific Impact

**OpenClaw Deployment:**
- ✅ Image: `ghcr.io/openclaw/openclaw:2026.3.1`
- ✅ CI: 24/24 passed
- ⚠️ **Risk**: If any agents use `nodes` tool with `system.run`, verify path usage

**Before merging:**
1. Check if any agents use bare command names in node execution
2. Update any `system.run` calls to use full paths
3. Test node operations in staging first

### ✅ Recommendation

**MERGE WITH CAUTION** - Minor version bump but contains breaking changes for node operations.

**LGTM** after breaking changes are verified in your environment.
