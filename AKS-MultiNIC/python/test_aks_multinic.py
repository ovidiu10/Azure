"""Offline Python CLI tests; never authenticate or create Azure resources."""

import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import uuid

import aks_multinic as cli


class SampleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        subscription = str(uuid.uuid4())
        self.vnet = (
            f"/subscriptions/{subscription}/resourceGroups/test-group/"
            "providers/Microsoft.Network/virtualNetworks/test-vnet"
        )
        self.config = {
            "subscriptionId": subscription, "resourceGroup": "test-group",
            "clusterName": "test-cluster", "nodePoolName": "nicpool",
            "namespace": "test-namespace", "podName": "test-pod",
            "claimTemplateName": "test-claim", "vmSize": "Standard_D8s_v5",
            "secondarySubnetIds": [f"{self.vnet}/subnets/secondary"],
            "image": "nicolaka/netshoot:v0.14", "nodeCount": 1,
        }
        self.config_path = self.directory / "config.json"
        self.output_dir = self.directory / "output with spaces"
        self.save_config()
        self.cluster = {
            "kubernetesVersion": "1.35.2", "location": "eastus",
            "networkProfile": {"networkPlugin": "azure"},
        }
        self.pools = [{"name": "system", "vnetSubnetId": f"{self.vnet}/subnets/primary"}]
        self.sku = {
            "name": self.config["vmSize"],
            "capabilities": [{"name": "MaxNetworkInterfaces", "value": "4"}],
            "restrictions": [],
        }
        self.interfaces = [
            {"ifname": "lo", "addr_info": [{"scope": "host"}]},
            {"ifname": "eth0", "addr_info": [{"scope": "global"}]},
            {"ifname": "net1", "addr_info": [{"scope": "global"}]},
        ]
        self.calls = []
        self.feature_state = "Registered"
        self.provider_state = "Registered"
        self.existing_pod = False
        self.missing_class = False
        self.kubeconfig_paths = []

    def save_config(self):
        self.config_path.write_text(json.dumps(self.config), encoding="utf-8")

    def run_cli(self, action, *flags):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return cli.main([
                action, "--config", str(self.config_path),
                "--output-dir", str(self.output_dir), *flags,
            ])

    def fake_tool(self, command, arguments):
        self.calls.append((command, arguments))
        if command == ["az"]:
            prefix = tuple(arguments[:3])
            if prefix[:2] == ("aks", "show"):
                return json.dumps(self.cluster)
            if prefix[:2] == ("aks", "get-credentials"):
                path = Path(arguments[arguments.index("--file") + 1])
                path.write_text("temporary credentials", encoding="utf-8")
                self.kubeconfig_paths.append(path)
                return ""
            if prefix[:2] == ("extension", "show"):
                return '{"version":"1.0"}'
            if "--help" in arguments:
                return "--secondary-network-interfaces"
            if prefix[:2] == ("feature", "show"):
                return self.feature_state
            if prefix[:2] == ("provider", "show"):
                return self.provider_state
            if prefix == ("aks", "nodepool", "list"):
                return json.dumps(self.pools)
            if prefix == ("network", "vnet", "subnet"):
                return ""
            if prefix[:2] == ("vm", "list-skus"):
                return json.dumps([self.sku])
            if prefix == ("aks", "nodepool", "add"):
                path = Path(arguments[arguments.index("--secondary-network-interfaces") + 1][1:])
                self.assertTrue(path.is_file())
                return '{"provisioningState":"Succeeded"}'
        if command == ["kubectl"]:
            self.assertEqual(arguments[0], "--kubeconfig")
            self.assertTrue(Path(arguments[1]).is_file())
            words = arguments[2:]
            if words[:2] == ["get", "namespace"]:
                return "namespace/test-namespace"
            if words[:2] == ["get", "pod"]:
                return "pod/test-pod" if self.existing_pod else ""
            if words[:2] == ["get", "resourceclaimtemplate"]:
                return ""
            if words[:2] == ["get", "deviceclass"]:
                return "" if self.missing_class else "deviceclass/standard-secondary-nic"
            if words[:2] == ["get", "daemonset"]:
                return "managed-driver-ready"
            if words[0] in ("wait", "delete"):
                return ""
            if words[0] == "apply":
                manifest = json.loads(Path(words[2]).read_text(encoding="utf-8"))
                self.assertEqual(len(manifest["items"]), 2)
                return "configured"
            if words[-4:] == ["ip", "-j", "address", "show"]:
                return json.dumps(self.interfaces)
            if words[-3:] == ["ip", "route", "show"]:
                return "secondary subnet route"
            if words[:2] == ["get", "resourceclaims"]:
                return "allocated"
        self.fail(f"Unexpected tool call: {command!r} {arguments!r}")

    @contextlib.contextmanager
    def fake_commands(self):
        with (
            patch.object(cli, "tool_command", side_effect=lambda name: [name]),
            patch.object(cli, "run_tool", side_effect=self.fake_tool),
        ):
            yield

    def test_render_is_offline_and_template_is_wired(self):
        with patch.object(cli, "tool_command", side_effect=AssertionError("Not offline")):
            self.assertEqual(self.run_cli("render"), 0)
        nics = json.loads((self.output_dir / "secondary-nics.json").read_text(encoding="utf-8"))
        self.assertIsInstance(nics, list)
        self.assertEqual(nics[0]["vnetSubnetId"], self.config["secondarySubnetIds"][0])
        manifest = json.loads((self.output_dir / "workload.json").read_text(encoding="utf-8"))
        claim, pod = manifest["items"]
        self.assertEqual(claim["metadata"]["name"], pod["spec"]["resourceClaims"][0]["resourceClaimTemplateName"])
        self.assertEqual(pod["spec"]["nodeSelector"]["kubernetes.azure.com/agentpool"], self.config["nodePoolName"])
        self.assertEqual(claim["spec"]["spec"]["devices"]["requests"][0]["exactly"]["count"], 1)
        self.assertNotIn("<", json.dumps(manifest))
        self.assertFalse(pod["spec"]["automountServiceAccountToken"])

    def test_dry_run_has_no_commands_or_writes(self):
        for action in ("render", "deploy", "verify", "remove-workload"):
            with self.subTest(action=action), patch.object(cli, "tool_command", side_effect=AssertionError("Tool called")):
                self.assertEqual(self.run_cli(action, "--dry-run"), 0)
                self.assertFalse(self.output_dir.exists())

    def test_deploy_and_verify_are_subscription_scoped(self):
        with self.fake_commands():
            self.assertEqual(self.run_cli("deploy", "--yes"), 0)
            self.assertEqual(self.run_cli("verify"), 0)
        for command, arguments in self.calls:
            if command == ["az"] and arguments[0] != "extension" and "--help" not in arguments:
                self.assertEqual(arguments[arguments.index("--subscription") + 1], self.config["subscriptionId"])
        additions = [args for command, args in self.calls if args[:3] == ["aks", "nodepool", "add"] and "--help" not in args]
        self.assertEqual(len(additions), 1)
        self.assertIn("Linux", additions[0])
        self.assertIn("User", additions[0])
        self.assertIn("@" + str(self.output_dir / "secondary-nics.json"), additions[0])
        self.assertTrue(self.kubeconfig_paths)
        self.assertTrue(all(not path.exists() for path in self.kubeconfig_paths))

    def test_remove_deletes_only_configured_workload(self):
        with self.fake_commands():
            self.assertEqual(self.run_cli("remove-workload", "--yes"), 0)
        deletions = [args[2:] for command, args in self.calls if command == ["kubectl"] and args[2] == "delete"]
        self.assertEqual([args[:3] for args in deletions], [
            ["delete", "pod", self.config["podName"]],
            ["delete", "resourceclaimtemplate", self.config["claimTemplateName"]],
        ])
        self.assertTrue(all("--namespace" in args and "--timeout=600s" in args for args in deletions))
        self.assertFalse(any(command == ["az"] and "delete" in args for command, args in self.calls))

    def test_unaddressed_secondary_interface_fails_verification(self):
        self.interfaces[-1]["addr_info"] = [{"scope": "link"}]
        with self.fake_commands():
            self.assertEqual(self.run_cli("verify"), 1)
        self.assertTrue(all(not path.exists() for path in self.kubeconfig_paths))

    def test_preflight_failures_do_not_create_pool(self):
        scenarios = ("version", "cni", "feature", "provider", "pool", "vnet", "nics", "sku", "pod")
        for scenario in scenarios:
            with self.subTest(scenario=scenario):
                self.setUp()
                if scenario == "version":
                    self.cluster["kubernetesVersion"] = "1.34.9"
                elif scenario == "cni":
                    self.cluster["networkProfile"]["networkPlugin"] = "kubenet"
                elif scenario == "feature":
                    self.feature_state = "Registering"
                elif scenario == "provider":
                    self.provider_state = "Registering"
                elif scenario == "pool":
                    self.pools[0]["name"] = self.config["nodePoolName"]
                elif scenario == "vnet":
                    self.pools[0]["vnetSubnetId"] = f"{self.vnet}-other/subnets/primary"
                elif scenario == "nics":
                    self.sku["capabilities"][0]["value"] = "1"
                elif scenario == "sku":
                    self.sku["restrictions"] = [{"type": "Location"}]
                elif scenario == "pod":
                    self.existing_pod = True
                with self.fake_commands():
                    self.assertEqual(self.run_cli("deploy", "--yes"), 1)
                self.assertFalse(any("--mode" in args for _, args in self.calls))
                self.assertTrue(all(not path.exists() for path in self.kubeconfig_paths))

    def test_driver_timeout_keeps_created_pool_and_cleans_credentials(self):
        self.missing_class = True
        with self.fake_commands(), patch.object(cli.time, "monotonic", side_effect=[0, 601]):
            self.assertEqual(self.run_cli("deploy", "--yes"), 1)
        self.assertTrue(any("--mode" in args for _, args in self.calls))
        self.assertFalse(any("delete" in args for _, args in self.calls))
        self.assertTrue(all(not path.exists() for path in self.kubeconfig_paths))

    def test_noninteractive_changes_require_yes(self):
        for action in ("deploy", "remove-workload"):
            with patch.object(cli.sys.stdin, "isatty", return_value=False), self.fake_commands():
                self.assertEqual(self.run_cli(action), 1)
                self.assertFalse(self.calls)

    def test_interactive_cancel_is_side_effect_free(self):
        with patch.object(cli.sys.stdin, "isatty", return_value=True), patch("builtins.input", return_value="no"), self.fake_commands():
            self.assertEqual(self.run_cli("deploy"), 0)
        self.assertFalse(self.calls)

    def test_invalid_configurations(self):
        original = copy.deepcopy(self.config)
        for name, value in (
            ("nodePoolName", "INVALID"), ("nodeCount", True), ("nodeCount", 0),
            ("subscriptionId", "<subscription-id>"), ("namespace", "a" * 64),
            ("image", "image:latest"), ("image", "image@sha256:invalid"),
            ("image", "image"), ("secondarySubnetIds", []), ("podName", "--flag"),
            ("secondarySubnetIds", [self.config["secondarySubnetIds"][0], f"{self.vnet}-other/subnets/secondary"]),
        ):
            with self.subTest(name=name, value=value):
                self.config = {**original, name: value}
                self.save_config()
                with self.assertRaises(cli.SampleError):
                    cli.load_config(self.config_path)

    def test_repeated_subnet_and_bom_config(self):
        self.config["secondarySubnetIds"] *= 2
        self.config_path.write_text(json.dumps(self.config), encoding="utf-8-sig")
        self.assertEqual(self.run_cli("render"), 0)
        self.assertEqual(len(json.loads((self.output_dir / "secondary-nics.json").read_text())), 2)

    def test_pinned_digest_is_supported(self):
        self.config["image"] = "registry.example/diagnostics@sha256:" + "a" * 64
        self.save_config()
        self.assertEqual(self.run_cli("render"), 0)


class ToolTests(unittest.TestCase):
    def test_unix_launcher(self):
        with patch.object(cli, "os", SimpleNamespace(name="posix")), patch.object(cli.shutil, "which", return_value="/usr/bin/az"):
            self.assertEqual(cli.tool_command("az"), ["/usr/bin/az"])

    def test_windows_msi_launcher_avoids_batch_shell(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            launcher = root / "wbin" / "az.cmd"
            interpreter = root / "python.exe"
            interpreter.touch()
            with patch.object(cli, "os", SimpleNamespace(name="nt")), patch.object(cli.shutil, "which", return_value=str(launcher)):
                self.assertEqual(cli.tool_command("az"), [str(interpreter), "-X", "utf8", "-IBm", "azure.cli"])

    def test_native_windows_kubectl(self):
        with patch.object(cli, "os", SimpleNamespace(name="nt")), patch.object(cli.shutil, "which", return_value="kubectl.exe"):
            self.assertEqual(cli.tool_command("kubectl"), ["kubectl.exe"])

    def test_missing_or_unsupported_launcher_fails(self):
        with patch.object(cli.shutil, "which", return_value=None), self.assertRaises(cli.SampleError):
            cli.tool_command("az")
        with patch.object(cli, "os", SimpleNamespace(name="nt")), patch.object(cli.shutil, "which", return_value="az.cmd"):
            with self.assertRaisesRegex(cli.SampleError, "MSI/WinGet"):
                cli.tool_command("az")

    def test_subprocess_argv_is_not_interpreted_by_shell(self):
        arguments = ["--file", "path with spaces & punctuation", "--name", "name;not-a-command"]
        with patch.object(cli.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout="success\n")) as run:
            self.assertEqual(cli.run_tool(["native-tool"], arguments), "success")
            self.assertEqual(run.call_args.args[0], ["native-tool", *arguments])
            self.assertIs(run.call_args.kwargs["shell"], False)

    def test_failure_and_msi_environment(self):
        command = ["bundled-python.exe", "-X", "utf8", "-IBm", "azure.cli"]
        with patch.object(cli.subprocess, "run", return_value=SimpleNamespace(returncode=7, stdout="")) as run:
            with self.assertRaisesRegex(cli.SampleError, "exit code 7"):
                cli.run_tool(command, ["extension", "show"])
            self.assertEqual(run.call_args.kwargs["env"]["AZ_INSTALLER"], "MSI")


if __name__ == "__main__":
    unittest.main()
