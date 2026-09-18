# CGE-AZ setup on Windows (PowerShell path)

A from-scratch Windows toolchain walkthrough, contributed by a launch-day learner
(thank you, Anbu) and edited for the repo. Use this when you're setting up on a
Windows machine without WSL; the main [SETUP.md](SETUP.md) still applies for
everything after the tools are installed, and its §7 covers the Git Bash
path-mangling quirks if you work in Git Bash instead of PowerShell.

## Azure CLI

From an administrator PowerShell:

```powershell
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindowsx64 -OutFile .\AzureCLI.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I', 'AzureCLI.msi', '/quiet'
Remove-Item .\AzureCLI.msi
```

Verify (`az -v`): you want `azure-cli 2.90.0` or later — 2.90 is the version the
course was validated on.

## Git

Install [Git for Windows](https://git-scm.com/download/win) and verify with
`git -v`.

## Terraform

1. Download the Windows amd64 zip from
   [releases.hashicorp.com/terraform](https://releases.hashicorp.com/terraform/)
   (>= 1.9; validated on 1.16.x) and unzip it.
2. Add the folder containing `terraform.exe` to your PATH: Search →
   "View advanced system settings" → Environment Variables → edit `Path` →
   add the folder. Apply, then open a NEW PowerShell window (or reboot).
3. Verify: `terraform -version`.

## Python + pip

```powershell
winget install Python.Python.3.14
```

Verify `python --version` and `pip --version` both resolve. pip ships with the
installer.

## conftest (needed from Domain 6)

Via [scoop](https://scoop.sh):

```powershell
scoop install conftest
```

Verify: `conftest --version`.

## Registering the resource providers (PowerShell equivalent)

`labs/00-setup/register-providers.sh` is a bash script. The PowerShell
equivalent of its core loop:

```powershell
"Microsoft.Management", "Microsoft.OperationalInsights", "Microsoft.Security",
"Microsoft.DocumentDB", "Microsoft.Web", "Microsoft.Storage", "Microsoft.Insights",
"Microsoft.PolicyInsights" | ForEach-Object { az provider register --namespace $_ }
```

Verify they registered:

```powershell
az provider list --query "[?registrationState=='Registered'].{Namespace:namespace, Status:registrationState}" --output table
```

## If management-group creation fails with AuthorizationFailed

On most fresh personal tenants, Lab 1's `az account management-group create`
just works. If yours returns `AuthorizationFailed`, your tenant restricts
management-group creation and you (as Global Administrator of your own tenant)
may need to [elevate access to the root scope](https://learn.microsoft.com/en-us/azure/role-based-access-control/elevate-access-global-admin)
once, create the hierarchy, then **turn the elevation back off** — it's a
break-glass setting, not something to leave enabled. Corporate tenants: see the
tenancy note in SETUP.md; you likely can't (and shouldn't) elevate there.
