#!/usr/bin/env python3
"""Contract tests for the LiteLLM MCP migration manifests."""

from __future__ import annotations

import fnmatch
import itertools
import json
import subprocess
import unittest
from pathlib import Path
from typing import Any, Iterable

import yaml
from yaml.events import AliasEvent


ROOT = Path(__file__).resolve().parents[1]
APPS_ROOT = ROOT / "kubernetes" / "apps"
LLM_ROOT = APPS_ROOT / "base" / "llm"
LITELLM_ROOT = LLM_ROOT / "litellm"
MCP_ROOT = LITELLM_ROOT / "mcp"
OLD_KUBECTL_RBAC = (
    "kubernetes/apps/base/llm/toolhive/mcp-servers/kubectl-mcp/rbac.yaml"
)
RBAC_BASELINE = "272877aa14b0ab61035a1d73ad2d108e48887b72"
CONSUMERS = {
    "hermes": {
        "url": "http://litellm.llm:4000/mcp",
        "header": "Authorization",
        "secret": "litellm-mcp-key-hermes",
    },
    "openclaw": {
        "url": "http://litellm.llm:4000/mcp",
        "header": "Authorization",
        "secret": "litellm-mcp-key-openclaw",
    },
    "opencode": {
        "url": "http://litellm.llm:4000/mcp",
        "header": "Authorization",
        "secret": "litellm-mcp-key-opencode",
    },
}
ALIASES = {
    "arr",
    "dispatch",
    "flux",
    "github",
    "grafana",
    "ha",
    "kubectl",
    "marketplace",
    "plan_shop_eat",
    "seerr",
    "talos",
    "unifi_network",
}
CLUSTERS = ("main", "utility", "test")
PROXY_MCP_SECRET_TARGETS = {
    "litellm-mcp-sonarr",
    "litellm-mcp-radarr",
    "litellm-mcp-prowlarr",
    "litellm-mcp-seerr",
    "litellm-mcp-github",
    "litellm-mcp-dispatch",
}
# Talos creates this Secret from the namespaced talos.dev ServiceAccount.
EXTERNAL_SECRET_TARGETS: dict[str, set[str] | None] = {"talos-mcp-talosconfig": None}


def yaml_files(root: Path) -> Iterable[Path]:
    for suffix in ("*.yaml", "*.yml"):
        yield from root.rglob(suffix)


class KubernetesLoader(yaml.SafeLoader):
    """Accept duplicate anchors and custom scalar tags present in Kubernetes YAML."""

    def compose_node(self, parent: yaml.Node | None, index: Any) -> yaml.Node:
        if self.check_event(AliasEvent):
            return super().compose_node(parent, index)
        event = self.peek_event()
        if event.anchor is not None:
            self.anchors.pop(event.anchor, None)
        return super().compose_node(parent, index)


def construct_value(loader: KubernetesLoader, node: yaml.Node) -> Any:
    return loader.construct_scalar(node)


KubernetesLoader.add_constructor("tag:yaml.org,2002:value", construct_value)
KubernetesLoader.add_multi_constructor("!", lambda loader, tag, node: loader.construct_scalar(node))


def documents(path: Path) -> list[dict[str, Any]]:
    try:
        with path.open(encoding="utf-8") as stream:
            return [doc for doc in yaml.load_all(stream, Loader=KubernetesLoader) if isinstance(doc, dict)]
    except yaml.YAMLError as error:
        raise AssertionError(f"invalid YAML in {path}: {error}") from error


def scalar_strings(value: Any) -> Iterable[str]:
    if isinstance(value, dict):
        for child in itertools.chain(value.keys(), value.values()):
            yield from scalar_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from scalar_strings(child)
    elif isinstance(value, str):
        yield value


def has_key(value: Any, sought: str) -> bool:
    if isinstance(value, dict):
        return sought in value or any(has_key(child, sought) for child in value.values())
    if isinstance(value, list):
        return any(has_key(child, sought) for child in value)
    return False


def permission_atoms(doc: dict[str, Any]) -> list[tuple[str, str, str, str | None]]:
    """Expand Kubernetes RBAC rule dimensions for a conservative comparison."""
    atoms = []
    role_rules = doc.get("rules", [])
    if not isinstance(role_rules, list):
        return atoms
    for rule in role_rules:
        if not isinstance(rule, dict):
            continue
        if rule.get("nonResourceURLs"):
            for url, verb in itertools.product(rule["nonResourceURLs"], rule.get("verbs", [])):
                atoms.append(("<non-resource>", str(url), str(verb), None))
            continue
        groups = rule.get("apiGroups", [])
        resources = rule.get("resources", [])
        names = rule.get("resourceNames") or [None]
        for group, resource, verb, name in itertools.product(
            groups, resources, rule.get("verbs", []), names
        ):
            atoms.append((str(group), str(resource), str(verb), name))
    return atoms


def grant_covers(
    baseline: tuple[str, str, str, str | None],
    current: tuple[str, str, str, str | None],
) -> bool:
    for allowed, requested in zip(baseline[:3], current[:3]):
        if allowed == "<non-resource>" or requested == "<non-resource>":
            if allowed != requested:
                return False
            continue
        if not fnmatch.fnmatchcase(requested, allowed):
            return False
    allowed_name, requested_name = baseline[3], current[3]
    return allowed_name is None or requested_name == allowed_name


def is_kubectl_role(path: Path, doc: dict[str, Any]) -> bool:
    if doc.get("kind") not in {"Role", "ClusterRole"}:
        return False
    searchable = " ".join([str(path), *scalar_strings(doc)]).lower()
    return "kubectl" in searchable and isinstance(doc.get("rules"), list)


def active_app_kustomizations() -> Iterable[Path]:
    """Yield base LLM Kustomize entrypoints outside retired MCP-related references."""
    for path in yaml_files(LLM_ROOT):
        if "virtualkeys" in path.parts:
            continue
        if "toolhive" in path.relative_to(LLM_ROOT).parts:
            continue
        if path.name in {"kustomization.yaml", "kustomization.yml"}:
            yield path


def mappings_with_key(value: Any, sought: str) -> Iterable[dict[str, Any]]:
    if isinstance(value, dict):
        if any(str(key).lower() == sought.lower() for key in value):
            yield value
        for child in value.values():
            yield from mappings_with_key(child, sought)
    elif isinstance(value, list):
        for child in value:
            yield from mappings_with_key(child, sought)


def active_mcp_docs() -> list[tuple[Path, dict[str, Any]]]:
    """Load only resources that the MCP Kustomization actually activates."""
    kustomization_path = MCP_ROOT / "kustomization.yaml"
    kustomizations = documents(kustomization_path)
    resources = [
        resource
        for doc in kustomizations
        for mapping in mappings_with_key(doc, "resources")
        for resource in mapping.get("resources", [])
        if isinstance(resource, str)
    ]
    active_docs = []
    for resource in resources:
        resource_path = MCP_ROOT / resource.removeprefix("./")
        if not resource_path.is_file():
            continue
        active_docs.extend((resource_path, doc) for doc in documents(resource_path))
    return active_docs


def external_secret_template_keys(
    external_secrets: Iterable[tuple[Path, dict[str, Any]]],
) -> dict[str, set[str] | None]:
    """Index generated Secret names and their explicitly templated data keys."""
    targets: dict[str, set[str] | None] = {}
    for _, doc in external_secrets:
        if doc.get("kind") != "ExternalSecret":
            continue
        spec = doc.get("spec", {})
        target = spec.get("target", {}) if isinstance(spec, dict) else {}
        template = target.get("template", {}) if isinstance(target, dict) else {}
        data = template.get("data", {}) if isinstance(template, dict) else {}
        name = target.get("name") if isinstance(target, dict) else None
        if name:
            targets[name] = set(data) if isinstance(data, dict) else set()
    return targets


def secret_references(
    path: Path,
    doc: dict[str, Any],
    *,
    include_key_refs: bool = True,
    include_volume_refs: bool = True,
) -> Iterable[tuple[str, str, str | None, str | None]]:
    """Yield Secret name/key references from key refs and Secret-backed volumes."""
    source = str(path.relative_to(ROOT))
    if include_key_refs:
        for field in ("secretKeyRef", "authTokenRef"):
            for mapping in mappings_with_key(doc, field):
                reference = mapping.get(field)
                if isinstance(reference, dict):
                    yield source, field, reference.get("name"), reference.get("key")

    if not include_volume_refs:
        return
    for mapping in mappings_with_key(doc, "secret"):
        secret = mapping.get("secret")
        if not isinstance(secret, dict):
            continue
        name = secret.get("secretName") or secret.get("name")
        items = secret.get("items", [])
        if isinstance(items, list) and items:
            for item in items:
                if isinstance(item, dict):
                    yield source, "secretVolume", name, item.get("key")
        else:
            yield source, "secretVolume", name, None


def secret_reference_violations(
    references: Iterable[tuple[str, str, str | None, str | None]],
    external_secret_keys: dict[str, set[str] | None],
) -> list[str]:
    """Report Secret refs without a matching ExternalSecret target and template key."""
    violations = []
    for source, reference_type, name, key in references:
        if not name:
            violations.append(f"{source}: Secret reference has no target name")
        elif name not in external_secret_keys:
            violations.append(f"{source}: unknown Secret target {name!r}")
        elif reference_type != "secretVolume" and not key:
            violations.append(f"{source}: {reference_type} for Secret {name!r} has no key")
        elif key and external_secret_keys[name] is not None and key not in external_secret_keys[name]:
            violations.append(f"{source}: Secret {name!r} has no templated key {key!r}")
    return violations


class LiteLLMMCPMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not MCP_ROOT.is_dir():
            raise AssertionError(f"expected migrated MCP manifests at {MCP_ROOT}")
        cls.mcp_docs = active_mcp_docs()
        cls.server_docs = [
            (path, doc) for path, doc in cls.mcp_docs if doc.get("kind") == "LiteLLMMCPServer"
        ]
        cls.access_docs = [
            (path, doc)
            for path in yaml_files(LITELLM_ROOT / "mcp-access")
            if path.name != "kustomization.yaml"
            for doc in documents(path)
        ]
        external_secrets = [
            (path, doc) for path, doc in cls.mcp_docs if doc.get("kind") == "ExternalSecret"
        ]
        cls.secret_targets = external_secret_template_keys(external_secrets)
        cls.secret_targets.update(EXTERNAL_SECRET_TARGETS)

    def test_all_expected_aliases_are_configured(self) -> None:
        aliases = [
            doc.get("spec", {}).get("alias")
            for _, doc in self.server_docs
            if isinstance(doc.get("spec"), dict)
        ]
        self.assertEqual(12, len(self.server_docs), "expected twelve LiteLLMMCPServer definitions")
        self.assertEqual(ALIASES, set(aliases), f"LiteLLMMCPServer aliases differ: {sorted(ALIASES ^ set(aliases))}")
        self.assertEqual(12, len(set(aliases)), "each LiteLLMMCPServer alias must be defined once")
        for path, doc in self.server_docs:
            with self.subTest(server=doc.get("metadata", {}).get("name")):
                self.assertEqual("LiteLLMMCPServer", doc.get("kind"))
                self.assertTrue(doc.get("spec", {}).get("alias"), f"{path.name} has no alias")

    def test_operator_workloads_and_transports_match_the_cutover(self) -> None:
        workloads = [
            doc
            for _, doc in self.server_docs
            if isinstance(doc.get("spec"), dict)
            and "workload" in doc["spec"]
            and isinstance(doc["spec"].get("workload"), dict)
            and "image" in doc["spec"]["workload"]
        ]
        self.assertEqual(6, len(workloads), "expected six operator-managed MCP workloads")
        workload_names = {doc.get("spec", {}).get("alias") for doc in workloads}
        self.assertEqual(
            {"flux", "ha", "kubectl", "marketplace", "talos", "unifi_network"},
            workload_names,
            "operator-managed MCP workload set changed",
        )

        stdio = [
            doc
            for _, doc in self.server_docs
            if doc.get("spec", {}).get("transport") == "stdio"
            and "/opt/mcp/launch.py" in "\n".join(scalar_strings(doc))
        ]
        self.assertEqual(4, len(stdio), "expected four stdio subprocess definitions using /opt/mcp/launch.py")
        for doc in stdio:
            with self.subTest(server=doc.get("metadata", {}).get("name")):
                self.assertEqual("python3", doc.get("spec", {}).get("params", {}).get("command"))
                self.assertEqual(
                    ["/opt/mcp/launch.py", doc.get("spec", {}).get("alias")],
                    doc.get("spec", {}).get("params", {}).get("args"),
                )

        server_ids = []
        for _, doc in self.server_docs:
            spec = doc.get("spec", {})
            with self.subTest(server=doc.get("metadata", {}).get("name")):
                params = spec.get("params", {})
                self.assertIs(params.get("allow_all_keys"), False, "MCP server must not allow all keys")
                server_id = params.get("server_id")
                self.assertTrue(server_id, "MCP server must declare a stable server_id")
                self.assertEqual(spec.get("alias"), server_id, "server_id must match its stable alias")
                server_ids.append(server_id)
        self.assertEqual(len(server_ids), len(set(server_ids)), "MCP server_id values must be unique")

        remote = [
            doc
            for _, doc in self.server_docs
            if doc.get("spec", {}).get("transport") in {"http", "sse", "streamable-http"}
            and "workload" not in doc.get("spec", {})
        ]
        self.assertEqual(2, len(remote), "expected two remote MCP server definitions")
        remote_aliases = {doc.get("spec", {}).get("alias") for doc in remote}
        self.assertEqual({"grafana", "plan_shop_eat"}, remote_aliases, "remote MCP server set changed")

        ha = [doc for _, doc in self.server_docs if doc.get("spec", {}).get("alias") == "ha"]
        self.assertEqual(1, len(ha), "expected exactly one Home Assistant MCP server")
        ha_workload = ha[0].get("spec", {}).get("workload", {})
        ha_env = {item.get("name"): item.get("value") for item in ha_workload.get("env", [])}
        self.assertEqual("8086", ha_env.get("MCP_PORT"), "Home Assistant process must bind port 8086")
        self.assertEqual(8086, ha_workload.get("port"), "operator workload port must match Home Assistant bind port")
        self.assertEqual("/mcp", ha_workload.get("path"), "Home Assistant MCP endpoint path must be explicit")

        proxy_docs = documents(LITELLM_ROOT / "litellmproxy.yaml")
        proxy_text = "\n".join(scalar_strings(proxy_docs))
        self.assertNotIn("entrypoint", proxy_text.lower(), "LiteLLM proxy manifest must not override the image entrypoint")
        self.assertNotIn("entrypoint.sh", proxy_text.lower(), "LiteLLM proxy runtime entrypoint override found")

    def test_toolhive_is_absent_from_active_consumers(self) -> None:
        stale_refs = []
        for path in active_app_kustomizations():
            try:
                parsed = documents(path)
            except AssertionError:
                continue
            for doc in parsed:
                resources = doc.get("resources", [])
                if isinstance(resources, list):
                    stale_refs.extend(
                        f"{path.relative_to(ROOT)}: {value}"
                        for value in resources
                        if isinstance(value, str) and "toolhive" in value.lower()
                    )
        self.assertEqual([], stale_refs, "active LLM app Kustomizations still reference ToolHive")

        for cluster in CLUSTERS:
            cluster_root = APPS_ROOT / cluster / "llm"
            path = cluster_root / "kustomization.yaml"
            if cluster == "main":
                self.assertTrue(cluster_root.is_dir(), f"main LLM overlay directory is missing: {cluster_root.relative_to(ROOT)}")
                self.assertTrue(path.is_file(), f"main LLM overlay is missing: {path.relative_to(ROOT)}")
            if not path.is_file():
                continue
            parsed = documents(path)
            toolhive_resources = [
                item
                for doc in parsed
                for mapping in mappings_with_key(doc, "resources")
                for item in mapping.get("resources", [])
                if isinstance(item, str) and "toolhive" in item.lower()
            ]
            self.assertEqual(
                [],
                toolhive_resources,
                f"{path.relative_to(ROOT)} still lists a ToolHive consumer",
            )

        toolhive_root = LLM_ROOT / "toolhive"
        self.assertFalse(toolhive_root.exists(), "retired ToolHive source tree still exists")
        main_overlay = APPS_ROOT / "main" / "llm"
        self.assertFalse(
            (main_overlay / "toolhive.yaml").exists(),
            "main cluster still has the retired ToolHive Flux Kustomization",
        )

        active_custom_resources = []
        for path in yaml_files(APPS_ROOT):
            if "toolhive" in path.relative_to(APPS_ROOT).parts:
                continue
            if "virtualkeys" in path.parts:
                continue
            try:
                parsed = documents(path)
            except AssertionError:
                continue
            for doc in parsed:
                if "toolhive.stacklok.dev" in str(doc.get("apiVersion", "")).lower():
                    active_custom_resources.append(str(path.relative_to(ROOT)))
        self.assertEqual([], active_custom_resources, "ToolHive custom resources remain outside the retired source tree")

    def test_authentication_is_header_based_and_secret_backed(self) -> None:
        access_docs = [doc for _, doc in self.access_docs]
        search_allowlist_patterns = ("toolhive__find_tool", "toolhive__call_tool", "vmcp-mcp-gateway")
        access_by_kind_and_name = {
            (doc.get("kind"), doc.get("metadata", {}).get("name")): doc
            for doc in access_docs
        }

        for consumer, contract in CONSUMERS.items():
            with self.subTest(consumer=consumer):
                configmap = documents(LLM_ROOT / consumer / "configmap.yaml")[0]
                config_key = {
                    "hermes": "config.yaml",
                    "openclaw": "openclaw.json",
                    "opencode": "opencode.json",
                }[consumer]
                config_source = configmap.get("data", {}).get(config_key)
                self.assertIsInstance(config_source, str, f"{consumer} embedded config is missing")
                if consumer == "hermes":
                    consumer_config = yaml.safe_load(config_source)
                    mcp_servers = consumer_config.get("mcp_servers", {})
                    litellm_server = mcp_servers.get("litellm", {})
                    other_servers = {name: value for name, value in mcp_servers.items() if name != "litellm"}
                    server_urls = [server.get("url", "") for server in other_servers.values() if isinstance(server, dict)]
                    self.assertFalse(
                        any("toolhive" in url.lower() or "vmcp" in url.lower() for url in server_urls),
                        "Hermes MCP URLs still reference ToolHive/vMCP",
                    )
                    hermes_tools = consumer_config.get("tools", {})
                    hermes_text = yaml.safe_dump(consumer_config).lower()
                    self.assertFalse(
                        any(pattern in hermes_text for pattern in search_allowlist_patterns),
                        "Hermes config retains a stale MCP search allowlist entry",
                    )
                elif consumer == "opencode":
                    consumer_config = json.loads(config_source)
                    mcp_servers = consumer_config.get("mcp", {})
                    litellm_server = mcp_servers.get("litellm", {})
                    server_urls = [server.get("url", "") for name, server in mcp_servers.items() if name != "litellm" and isinstance(server, dict)]
                    self.assertFalse(
                        any("toolhive" in url.lower() or "vmcp" in url.lower() for url in server_urls),
                        f"{consumer} MCP URLs still reference ToolHive/vMCP",
                    )
                    opencode_text = json.dumps(consumer_config).lower()
                    self.assertFalse(
                        any(pattern in opencode_text for pattern in search_allowlist_patterns),
                        "OpenCode config retains a stale MCP search allowlist entry",
                    )
                else:
                    mcp_start = config_source.find("mcp: {")
                    self.assertNotEqual(-1, mcp_start, "OpenClaw MCP configuration is missing")
                    mcp_config = config_source[mcp_start:]
                    mcp_config = mcp_config[:mcp_config.find("\n  meta:", 1)]
                    server_start = mcp_config.find("servers: {")
                    self.assertNotEqual(-1, server_start, "OpenClaw MCP server list is missing")
                    server_block = mcp_config[server_start:]
                    server_end = server_block.find("\n    },\n  },")
                    self.assertNotEqual(-1, server_end, "OpenClaw MCP server list block is malformed")
                    server_block = server_block[:server_end]
                    litellm_start = server_block.find("      litellm: {")
                    context7_start = server_block.find("      context7: {")
                    self.assertNotEqual(-1, litellm_start, "OpenClaw LiteLLM MCP server entry is missing")
                    litellm_block = (
                        server_block[litellm_start:]
                        if context7_start == -1
                        else server_block[litellm_start:context7_start]
                    )
                    self.assertIn('url: "http://litellm.llm:4000/mcp"', litellm_block)
                    self.assertIn('Authorization: "Bearer $${LITELLM_MCP_API_KEY}"', litellm_block)
                    openclaw_text = config_source.lower()
                    self.assertFalse(
                        any(pattern in openclaw_text for pattern in search_allowlist_patterns),
                        "OpenClaw config retains a stale MCP search allowlist entry",
                    )
                    self.assertNotIn("toolhive", server_block.lower())
                    self.assertNotIn("vmcp", server_block.lower())
                    litellm_server = {
                        "url": "http://litellm.llm:4000/mcp",
                        "headers": {"Authorization": "Bearer $${LITELLM_MCP_API_KEY}"},
                    }
                self.assertIsInstance(litellm_server, dict, f"{consumer} LiteLLM MCP server entry is missing")
                self.assertEqual(contract["url"], litellm_server.get("url"), "consumer no longer targets LiteLLM /mcp")
                headers = {str(name).lower(): value for name, value in litellm_server.get("headers", {}).items()}
                self.assertIn(contract["header"].lower(), headers, "consumer MCP auth header is missing")
                self.assertEqual(
                    (
                        "Bearer {env:LITELLM_MCP_API_KEY}"
                        if consumer == "opencode"
                        else "Bearer $${LITELLM_MCP_API_KEY}"
                    ),
                    headers[contract["header"].lower()],
                    f"{consumer} does not send its MCP key as bearer auth",
                )

                workload_doc = documents(LLM_ROOT / consumer / "helmrelease.yaml")[0]
                secret_refs = []
                for mapping in mappings_with_key(workload_doc, "secretKeyRef"):
                    secret_ref = mapping.get("secretKeyRef")
                    if isinstance(secret_ref, dict):
                        secret_refs.append(secret_ref)
                self.assertIn(
                    {"name": contract["secret"], "key": "api-key"},
                    secret_refs,
                    f"{consumer} MCP key must use the expected Secret and api-key",
                )
                env_maps = [
                    mapping
                    for mapping in mappings_with_key(workload_doc, "LITELLM_MCP_API_KEY")
                    if isinstance(mapping.get("LITELLM_MCP_API_KEY"), dict)
                ]
                self.assertTrue(env_maps, f"{consumer} workload does not inject MCP key")
                self.assertTrue(
                    any(
                        env_map["LITELLM_MCP_API_KEY"].get("valueFrom", {}).get("secretKeyRef")
                        == {"name": contract["secret"], "key": "api-key"}
                        for env_map in env_maps
                        if isinstance(env_map["LITELLM_MCP_API_KEY"].get("valueFrom"), dict)
                    ),
                    f"{consumer} MCP key env var is not wired to its expected Secret",
                )
                if consumer == "hermes":
                    init_env = (
                        workload_doc.get("spec", {})
                        .get("values", {})
                        .get("controllers", {})
                        .get("hermes", {})
                        .get("initContainers", {})
                        .get("init", {})
                        .get("env", [])
                    )
                    self.assertIn(
                        {
                            "name": "LITELLM_MCP_API_KEY",
                            "valueFrom": {
                                "secretKeyRef": {"name": contract["secret"], "key": "api-key"}
                            },
                        },
                        init_env,
                        "Hermes init envsubst container must receive the MCP key",
                    )

                team_name = f"{consumer}-mcp"
                team = access_by_kind_and_name.get(("LiteLLMTeam", team_name))
                virtual_key = access_by_kind_and_name.get(("LiteLLMVirtualKey", team_name))
                self.assertIsNotNone(team, f"missing MCP team for {consumer}")
                self.assertIsNotNone(virtual_key, f"missing MCP virtual key for {consumer}")
                self.assertEqual(team_name, team.get("spec", {}).get("teamID"))
                self.assertEqual(team_name, virtual_key.get("spec", {}).get("teamID"))
                self.assertEqual(
                    ["no-default-models"],
                    team.get("spec", {}).get("models"),
                    f"{consumer} MCP team must not grant model access",
                )
                self.assertEqual(
                    ["no-default-models"],
                    virtual_key.get("spec", {}).get("models"),
                    f"{consumer} MCP key must not grant model access",
                )
                self.assertEqual(contract["secret"], virtual_key.get("spec", {}).get("secretName"))
                self.assertEqual("api-key", virtual_key.get("spec", {}).get("secretKey"))
                self.assertEqual(set(ALIASES), set(team.get("spec", {}).get("mcpServers", [])))

                external_secret = documents(LLM_ROOT / consumer / "externalsecret.yaml")
                self.assertTrue(
                    any(
                        doc.get("kind") == "ExternalSecret"
                        and doc.get("spec", {}).get("target", {}).get("name") == consumer
                        for doc in external_secret
                    ),
                    f"{consumer} must continue sourcing consumer credentials from ExternalSecret",
                )

    def test_mcp_secret_references_match_external_secret_targets_and_keys(self) -> None:
        references = [
            reference
            for path, doc in self.mcp_docs
            for reference in secret_references(path, doc)
        ]
        proxy_doc = documents(LITELLM_ROOT / "litellmproxy.yaml")[0]
        proxy_volume_refs = [
            (reference_type, name, key)
            for _, reference_type, name, key in secret_references(
                LITELLM_ROOT / "litellmproxy.yaml",
                proxy_doc,
                include_key_refs=False,
                include_volume_refs=True,
            )
        ]
        expected_proxy_secret_refs = {
            ("secretVolume", name, key)
            for name, keys in self.secret_targets.items()
            if name in PROXY_MCP_SECRET_TARGETS
            for key in keys
        }
        self.assertEqual(
            expected_proxy_secret_refs,
            set(proxy_volume_refs),
            "LiteLLM MCP Secret-backed volumes must match ExternalSecret targets and keys",
        )
        references.extend(
            secret_references(
                LITELLM_ROOT / "litellmproxy.yaml",
                proxy_doc,
                include_key_refs=False,
                include_volume_refs=True,
            )
        )
        violations = secret_reference_violations(references, self.secret_targets)
        self.assertEqual([], violations, "MCP Secret references must match declared targets and keys")

    def test_unknown_secret_reference_fails_the_contract(self) -> None:
        violations = secret_reference_violations(
            [("test.yaml", "secretKeyRef", "missing-secret", "token")],
            self.secret_targets,
        )
        self.assertEqual(["test.yaml: unknown Secret target 'missing-secret'"], violations)

    def test_consumer_mcp_secret_contract_remains_explicit(self) -> None:
        for consumer, contract in CONSUMERS.items():
            with self.subTest(consumer=consumer):
                path = LLM_ROOT / consumer / "helmrelease.yaml"
                references = {
                    (name, key)
                    for _, _, name, key in secret_references(path, documents(path)[0])
                }
                self.assertIn(
                    (contract["secret"], "api-key"),
                    references,
                    f"{consumer} MCP key must retain its expected Secret and api-key",
                )

    def test_no_plaintext_kubernetes_secrets_are_declared(self) -> None:
        violations = []
        for path, doc in self.mcp_docs:
            if doc.get("kind") == "Secret" and (doc.get("data") or doc.get("stringData")):
                violations.append(str(path.relative_to(ROOT)))
            if has_key(doc, "stringData"):
                violations.append(str(path.relative_to(ROOT)))
        self.assertEqual([], violations, "MCP manifests must not contain plaintext Secret payloads")

    def test_public_mcp_route_only_matches_the_mcp_path(self) -> None:
        route_path = LITELLM_ROOT / "mcp-httproute.yaml"
        self.assertTrue(route_path.is_file(), f"public MCP HTTPRoute is missing: {route_path}")
        routes = [doc for doc in documents(route_path) if doc.get("kind") == "HTTPRoute"]
        self.assertEqual(1, len(routes), "expected one dedicated public MCP HTTPRoute")
        rules = routes[0].get("spec", {}).get("rules", [])
        self.assertTrue(rules, "MCP HTTPRoute has no routing rules")
        for rule in rules:
            matches = rule.get("matches", []) if isinstance(rule, dict) else []
            self.assertTrue(matches, "public MCP route must not contain an unrestricted rule")
            for match in matches:
                path = match.get("path", {}) if isinstance(match, dict) else {}
                self.assertEqual("PathPrefix", path.get("type"), "MCP route must use a path-prefix match")
                self.assertEqual("/mcp", path.get("value"), "MCP route exposes a path outside /mcp")

    def test_kubectl_rbac_does_not_expand_from_the_migration_baseline(self) -> None:
        try:
            baseline_text = subprocess.check_output(
                ["git", "show", f"{RBAC_BASELINE}:{OLD_KUBECTL_RBAC}"],
                cwd=ROOT,
                text=True,
                stderr=subprocess.DEVNULL,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.fail(f"immutable RBAC baseline {RBAC_BASELINE} does not contain the prior manifest")

        baseline_docs = [
            doc
            for doc in yaml.load_all(baseline_text, Loader=KubernetesLoader)
            if isinstance(doc, dict)
        ]
        baseline_atoms = [atom for doc in baseline_docs for atom in permission_atoms(doc)]
        self.assertTrue(baseline_atoms, "the immutable prior kubectl RBAC baseline has no rules")

        candidates = [
            (path, doc)
            for path, doc in self.mcp_docs
            if is_kubectl_role(path, doc)
        ]
        self.assertTrue(candidates, "migrated kubectl Role or ClusterRole manifest is missing")
        candidate_names = {doc.get("metadata", {}).get("name") for _, doc in candidates}
        kubectl_roles = [
            (path, doc)
            for path, doc in self.mcp_docs
            if doc.get("kind") in {"Role", "ClusterRole"}
            and doc.get("metadata", {}).get("name") in candidate_names
        ]
        self.assertEqual(
            {"kubectl-mcp-readonly", "kubectl-mcp-readonly-explicit"},
            candidate_names,
            "kubectl read-only ClusterRole set changed",
        )

        kubectl_servers = [
            doc for _, doc in self.server_docs if doc.get("spec", {}).get("alias") == "kubectl"
        ]
        self.assertEqual(1, len(kubectl_servers), "expected exactly one kubectl MCP server")
        service_account_name = kubectl_servers[0].get("spec", {}).get("workload", {}).get("serviceAccountName")
        self.assertTrue(service_account_name, "kubectl MCP workload must explicitly select its RBAC ServiceAccount")

        service_accounts = [
            doc
            for _, doc in self.mcp_docs
            if doc.get("kind") == "ServiceAccount"
            and doc.get("metadata", {}).get("name") == service_account_name
        ]
        self.assertEqual(1, len(service_accounts), "kubectl workload ServiceAccount must be declared exactly once")
        self.assertEqual(
            service_account_name,
            service_accounts[0].get("metadata", {}).get("name"),
            "kubectl workload ServiceAccount name does not match its declaration",
        )

        bindings = [
            doc
            for _, doc in self.mcp_docs
            if doc.get("kind") in {"RoleBinding", "ClusterRoleBinding"}
            and any(
                subject.get("kind") == "ServiceAccount"
                and subject.get("name") == service_account_name
                for subject in doc.get("subjects", [])
                if isinstance(subject, dict)
            )
        ]
        expected_binding_names = {
            "kubectl-mcp-readonly",
            "kubectl-mcp-readonly-explicit",
        }
        self.assertEqual(
            expected_binding_names,
            {doc.get("metadata", {}).get("name") for doc in bindings},
            "kubectl RBAC bindings differ from the expected read-only bindings",
        )
        self.assertEqual(
            {"kubectl-mcp-readonly", "kubectl-mcp-readonly-explicit"},
            {doc.get("roleRef", {}).get("name") for doc in bindings},
            "kubectl RBAC binding role targets changed",
        )
        for binding in bindings:
            with self.subTest(binding=binding.get("metadata", {}).get("name")):
                self.assertEqual(
                    [{"kind": "ServiceAccount", "name": service_account_name, "namespace": "llm"}],
                    binding.get("subjects", []),
                    "kubectl RBAC binding must target only its workload ServiceAccount in llm",
                )
                role_name = binding.get("roleRef", {}).get("name")
                self.assertEqual(
                    binding.get("metadata", {}).get("name"),
                    role_name,
                    "kubectl RBAC binding must reference its same-named role",
                )
                self.assertTrue(
                    any(doc.get("metadata", {}).get("name") == role_name for _, doc in kubectl_roles),
                    "kubectl RBAC binding references a missing role",
                )

        violations = []
        for path, doc in candidates:
            for atom in permission_atoms(doc):
                if not any(grant_covers(old, atom) for old in baseline_atoms):
                    violations.append(f"{path.relative_to(ROOT)}: expanded RBAC grant {atom}")
        self.assertEqual([], violations, "kubectl RBAC grants exceed the immutable migration baseline")


if __name__ == "__main__":
    unittest.main()
