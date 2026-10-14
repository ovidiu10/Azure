#!/usr/bin/env python3
"""Public AKS DRANET sample CLI for Windows, Linux, and macOS (Python 3.10+)."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parent
SHARED = ROOT.parent / "shared"
DEVICE_CLASS = "standard-secondary-nic"
SUBNET_PATTERN = re.compile(
    r"^(/subscriptions/([^/]+)/resourceGroups/[^/]+/providers/"
    r"Microsoft\.Network/virtualNetworks/[^/]+)/subnets/[^/<>]+$",
    re.IGNORECASE,
)


class SampleError(Exception):
    """An actionable configuration, prerequisite, or command error."""


def load_config(path):
    config = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(config, dict):
        raise SampleError("Configuration must be a JSON object.")
    for name in (
        "subscriptionId", "resourceGroup", "clusterName", "nodePoolName",
        "namespace", "podName", "claimTemplateName", "vmSize", "image",
    ):
        value = config.get(name)
        if (
            not isinstance(value, str) or not value.strip()
            or re.search(r"[<>\x00-\x1f]", value) or value.startswith("-")
        ):
            raise SampleError(f"'{name}' must be supplied without placeholders or control characters.")
    try:
        uuid.UUID(config["subscriptionId"])
    except ValueError as error:
        raise SampleError("subscriptionId must be a subscription GUID.") from error
    if not re.fullmatch(r"[a-z][a-z0-9]{0,11}", config["nodePoolName"]):
        raise SampleError("nodePoolName must be 1-12 lowercase letters/digits, starting with a letter.")
    for name in ("namespace", "podName", "claimTemplateName"):
        value = config[name]
        if len(value) > 63 or not re.fullmatch(r"[a-z0-9](?:[-a-z0-9]*[a-z0-9])?", value):
            raise SampleError(f"'{name}' must be a lowercase DNS label of at most 63 characters.")
    image = config["image"]
    pinned_image = (
        re.fullmatch(r"[^@\s]+@sha256:[a-fA-F0-9]{64}", image) if "@" in image
        else re.fullmatch(r"[^@\s]+:[^/:\s]+", image)
    )
    if not pinned_image or image.lower().endswith(":latest"):
        raise SampleError("image must use an explicit non-latest tag or sha256 digest.")
    subnets = config.get("secondarySubnetIds")
    if not isinstance(subnets, list) or not subnets:
        raise SampleError("secondarySubnetIds must be a nonempty JSON array.")
    vnets = set()
    for subnet in subnets:
        match = SUBNET_PATTERN.fullmatch(subnet) if isinstance(subnet, str) else None
        if not match or re.search(r"[\x00-\x1f]", subnet):
            raise SampleError("Each secondarySubnetIds entry must be a complete Azure subnet resource ID.")
        if match[2].lower() != config["subscriptionId"].lower():
            raise SampleError("All secondary subnets must be in the configured subscription.")
        vnets.add(match[1].lower())
    if len(vnets) != 1:
        raise SampleError("All secondary NICs must use subnets in the same VNet.")
    count = config.get("nodeCount")
    if type(count) is not int or not 1 <= count <= 100:
        raise SampleError("nodeCount must be an integer between 1 and 100.")
    return config


def render(config, directory):
    manifest = json.loads((SHARED / "workload.template.json").read_text(encoding="utf-8"))
    claim, pod = manifest["items"]
    claim["metadata"].update(name=config["claimTemplateName"], namespace=config["namespace"])
    pod["metadata"].update(name=config["podName"], namespace=config["namespace"])
    pod["spec"]["nodeSelector"]["kubernetes.azure.com/agentpool"] = config["nodePoolName"]
    pod["spec"]["resourceClaims"][0]["resourceClaimTemplateName"] = config["claimTemplateName"]
    pod["spec"]["containers"][0]["image"] = config["image"]
    nics = [{"type": "Standard", "vnetSubnetId": subnet} for subnet in config["secondarySubnetIds"]]
    directory.mkdir(parents=True, exist_ok=True)
    nic_path = directory / "secondary-nics.json"
    manifest_path = directory / "workload.json"
    for path, value in ((nic_path, nics), (manifest_path, manifest)):
        path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        print(f"Rendered: {path}")
    return nic_path, manifest_path


def tool_command(name):
    executable = shutil.which(name)
    if not executable:
        raise SampleError(f"Required tool '{name}' was not found on PATH.")
    if os.name == "nt" and Path(executable).suffix.lower() in (".cmd", ".bat"):
        # Invoke the MSI install's Python directly, avoiding cmd.exe argument expansion.
        interpreter = Path(executable).parent.parent / "python.exe"
        if name != "az" or not interpreter.is_file():
            raise SampleError(
                f"Unsupported Windows batch launcher for '{name}'. "
                "Use the official Azure CLI MSI/WinGet installation and native kubectl."
            )
        return [str(interpreter), "-X", "utf8", "-IBm", "azure.cli"]
    return [executable]


def run_tool(command, arguments):
    env = os.environ.copy()
    if command[-1] == "azure.cli":
        env["AZ_INSTALLER"] = "MSI"
    result = subprocess.run(
        [*command, *arguments], check=False, stdout=subprocess.PIPE,
        text=True, encoding="utf-8", env=env, shell=False,
    )
    if result.returncode:
        raise SampleError(f"{Path(command[0]).name} failed with exit code {result.returncode}. See the error above.")
    return result.stdout.strip()


class Sample:
    def __init__(self, config, timeout):
        self.config = config
        self.timeout = timeout
        self.az_command = tool_command("az")
        self.kubectl_command = tool_command("kubectl")
        self.kubeconfig = None

    def az(self, *arguments):
        return run_tool(
            self.az_command,
            [*arguments, "--subscription", self.config["subscriptionId"], "--only-show-errors"],
        )

    def kubectl(self, *arguments):
        if self.kubeconfig is None:
            raise SampleError("An isolated kubeconfig is required before calling kubectl.")
        return run_tool(self.kubectl_command, ["--kubeconfig", str(self.kubeconfig), *arguments])

    def cluster_args(self):
        return ["-g", self.config["resourceGroup"], "--cluster-name", self.config["clusterName"]]

    def wait_for_pod(self):
        self.kubectl(
            "wait", "--for=condition=Ready", f"pod/{self.config['podName']}",
            "--namespace", self.config["namespace"], f"--timeout={self.timeout}s",
        )

    def verify(self):
        self.wait_for_pod()
        interfaces = json.loads(self.kubectl(
            "exec", "--namespace", self.config["namespace"], self.config["podName"],
            "--", "ip", "-j", "address", "show",
        ))
        primary = [nic for nic in interfaces if nic["ifname"] == "eth0"]
        secondary = [
            nic for nic in interfaces
            if nic["ifname"] not in ("lo", "eth0")
            and any(address["scope"] == "global" for address in nic["addr_info"])
        ]
        if len(primary) != 1 or not secondary:
            raise SampleError("Expected CNI eth0 plus an addressed secondary interface. Inspect pod and DRANET events.")
        print(json.dumps(interfaces, indent=2))
        print(self.kubectl(
            "exec", "--namespace", self.config["namespace"], self.config["podName"],
            "--", "ip", "route", "show",
        ))
        print(self.kubectl("get", "resourceclaims", "--namespace", self.config["namespace"], "-o", "wide"))

    def preflight(self, cluster):
        version = re.fullmatch(r"(\d+)\.(\d+)(?:\.\d+)?", cluster["kubernetesVersion"])
        if not version or tuple(map(int, version.groups())) < (1, 35):
            raise SampleError("The public AKS configuration guide requires Kubernetes 1.35 or later.")
        if cluster["networkProfile"]["networkPlugin"] != "azure":
            raise SampleError("This sample requires AKS-managed Azure CNI, optionally powered by Cilium.")
        extension = json.loads(run_tool(
            self.az_command, ["extension", "show", "--name", "aks-preview", "--only-show-errors", "-o", "json"],
        ))
        if not extension.get("version"):
            raise SampleError("Install or update the aks-preview extension first.")
        if "--secondary-network-interfaces" not in run_tool(self.az_command, ["aks", "nodepool", "add", "--help"]):
            raise SampleError("Update aks-preview to expose --secondary-network-interfaces.")
        for arguments, message in (
            (
                ["feature", "show", "--namespace", "Microsoft.ContainerService",
                 "--name", "NetworkingMultiNICPreview", "--query", "properties.state", "-o", "tsv"],
                "Register NetworkingMultiNICPreview, wait for Registered, then refresh the provider.",
            ),
            (
                ["provider", "show", "--namespace", "Microsoft.ContainerService",
                 "--query", "registrationState", "-o", "tsv"],
                "Wait for Microsoft.ContainerService provider registration to complete.",
            ),
        ):
            if self.az(*arguments) != "Registered":
                raise SampleError(message)
        pools = json.loads(self.az("aks", "nodepool", "list", *self.cluster_args(), "-o", "json"))
        if any(pool["name"] == self.config["nodePoolName"] for pool in pools):
            raise SampleError("nodePoolName already exists. Deploy requires a new pool; use verify for an existing deployment.")
        primary_subnets = [pool["vnetSubnetId"] for pool in pools if pool.get("vnetSubnetId")]
        if not primary_subnets:
            raise SampleError("This sample requires a BYO-VNet cluster with explicit node subnet IDs.")
        primary_vnet = primary_subnets[0].rsplit("/subnets/", 1)[0]
        secondary_vnet = SUBNET_PATTERN.fullmatch(self.config["secondarySubnetIds"][0])[1]
        if primary_vnet.lower() != secondary_vnet.lower():
            raise SampleError("Secondary subnets must belong to the same VNet as the primary NICs.")
        for subnet in dict.fromkeys(self.config["secondarySubnetIds"]):
            self.az("network", "vnet", "subnet", "show", "--ids", subnet, "-o", "none")
        skus = json.loads(self.az(
            "vm", "list-skus", "--location", cluster["location"], "--resource-type", "virtualMachines",
            "--size", self.config["vmSize"], "--all", "-o", "json",
        ))
        matches = [sku for sku in skus if sku["name"] == self.config["vmSize"]]
        if len(matches) != 1:
            raise SampleError("The requested VM size was not found in the cluster region.")
        max_nics = [cap["value"] for cap in matches[0]["capabilities"] if cap["name"] == "MaxNetworkInterfaces"]
        if len(max_nics) != 1 or int(max_nics[0]) < 1 + len(self.config["secondarySubnetIds"]):
            raise SampleError("VM size must support one primary NIC plus every secondary NIC.")
        if any(restriction["type"] == "Location" for restriction in matches[0]["restrictions"]):
            raise SampleError("The VM size has a location restriction for this subscription.")
        for kind, name in (("pod", self.config["podName"]), ("resourceclaimtemplate", self.config["claimTemplateName"])):
            if self.kubectl(
                "get", kind, name, "--namespace", self.config["namespace"], "--ignore-not-found=true", "-o", "name",
            ):
                raise SampleError(f"The configured {kind} already exists. Choose a new name.")
        return primary_subnets[0]

    def deploy(self, cluster, directory):
        primary_subnet = self.preflight(cluster)
        nic_path, manifest_path = render(self.config, directory)
        print(self.az(
            "aks", "nodepool", "add", *self.cluster_args(), "--name", self.config["nodePoolName"],
            "--mode", "User", "--os-type", "Linux", "--node-vm-size", self.config["vmSize"],
            "--node-count", str(self.config["nodeCount"]), "--vnet-subnet-id", primary_subnet,
            "--secondary-network-interfaces", f"@{nic_path}", "-o", "json",
        ))
        deadline = time.monotonic() + self.timeout
        while not self.kubectl("get", "deviceclass", DEVICE_CLASS, "--ignore-not-found=true", "-o", "name"):
            if time.monotonic() >= deadline:
                raise SampleError("Timed out waiting for the DRANET DeviceClass. The new pool remains billable.")
            time.sleep(5)
        print(self.kubectl("get", "daemonset", "-A"))
        print(self.kubectl("apply", "-f", str(manifest_path)))
        self.verify()

    def remove_workload(self):
        for kind, name in (("pod", self.config["podName"]), ("resourceclaimtemplate", self.config["claimTemplateName"])):
            print(self.kubectl(
                "delete", kind, name, "--namespace", self.config["namespace"],
                "--ignore-not-found=true", "--wait=true", f"--timeout={self.timeout}s",
            ))
        print("Workload removed. Namespace, node pool, and Azure resources remain; node costs continue.")

    def execute(self, action, directory):
        cluster = json.loads(self.az(
            "aks", "show", "-g", self.config["resourceGroup"], "-n", self.config["clusterName"], "-o", "json",
        ))
        with tempfile.TemporaryDirectory(prefix="aks-multinic-") as temporary:
            self.kubeconfig = Path(temporary) / "kubeconfig"
            try:
                self.az(
                    "aks", "get-credentials", "-g", self.config["resourceGroup"], "-n", self.config["clusterName"],
                    "--file", str(self.kubeconfig), "-o", "none",
                )
                self.kubectl("get", "namespace", self.config["namespace"], "-o", "name")
                if action == "deploy":
                    self.deploy(cluster, directory)
                elif action == "verify":
                    self.verify()
                elif action == "remove-workload":
                    self.remove_workload()
                else:
                    raise SampleError(f"Unsupported live action: {action}")
            finally:
                self.kubeconfig = None


def timeout_seconds(value):
    number = int(value)
    if not 30 <= number <= 3600:
        raise argparse.ArgumentTypeError("timeout must be between 30 and 3600 seconds")
    return number


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("render", "deploy", "verify", "remove-workload"))
    parser.add_argument("--config", required=True, type=Path, help="Path to your populated JSON configuration")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "generated")
    parser.add_argument("--timeout", type=timeout_seconds, default=600, help="Readiness timeout in seconds (default: 600)")
    parser.add_argument("--dry-run", action="store_true", help="Show target without tool calls or file writes; not a live preflight")
    parser.add_argument("--yes", action="store_true", help="Confirm deployment or workload deletion without an interactive prompt")
    args = parser.parse_args(argv)
    try:
        config = load_config(args.config)
        directory = args.output_dir.resolve()
        target = f"{config['subscriptionId']}/{config['resourceGroup']}/{config['clusterName']}, namespace {config['namespace']}"
        if args.dry_run:
            print(f"Dry run: {args.action} on {target}; output directory {directory}. No commands or writes.")
            return 0
        if args.action == "render":
            render(config, directory)
            return 0
        if args.action in ("deploy", "remove-workload") and not args.yes:
            operation = (
                f"Create billable pool '{config['nodePoolName']}' and pod '{config['podName']}'"
                if args.action == "deploy" else
                f"Delete pod '{config['podName']}' and claim template '{config['claimTemplateName']}'"
            )
            print(f"{operation} on {target}.")
            if not sys.stdin.isatty():
                raise SampleError("Noninteractive changes require --yes. Use --dry-run to review the target first.")
            if input("Type yes to continue: ").strip() != "yes":
                print("Cancelled; no commands or writes.")
                return 0
        Sample(config, args.timeout).execute(args.action, directory)
        return 0
    except (SampleError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        if args.action == "deploy":
            print("Deployment is not rolled back automatically; any created pool remains billable.", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("Interrupted; any created resources remain. Review the target before retrying.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
