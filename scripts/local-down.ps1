# Delete the local kind cluster. Run from repo root:
#   .\scripts\local-down.ps1

$ErrorActionPreference = "Stop"
$ClusterName = "angular-micro"

if (kind get clusters | Select-String "^$ClusterName$") {
    Write-Host "==> Deleting kind cluster '$ClusterName'..."
    kind delete cluster --name $ClusterName
    Write-Host "==> Done."
} else {
    Write-Host "    No cluster named '$ClusterName' is running."
}
