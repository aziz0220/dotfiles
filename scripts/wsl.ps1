<#
.SYNOPSIS
Creates, bootstraps, launches, or removes a WSL distro.

.DESCRIPTION
The up action installs a named WSL2 distro when needed, creates a normal Linux
user, runs the dotfiles bootstrap, validates the result, and launches the
completed distro. By default, Ubuntu-26.04 is registered as the separate
Ubuntu-26.04-Dotfiles instance, leaving an existing Ubuntu-26.04 instance
untouched. The down action optionally exports and then unregisters the distro
after explicit confirmation.

.EXAMPLE
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/aziz0220/dotfiles/main/scripts/wsl.ps1')))

.EXAMPLE
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/aziz0220/dotfiles/main/scripts/wsl.ps1'))) up Ubuntu-26.04 -Name Work-26

.EXAMPLE
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/aziz0220/dotfiles/main/scripts/wsl.ps1'))) down Ubuntu-26.04 -ExportPath "$HOME\Backups\Ubuntu-26.04-Dotfiles.tar"
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("up", "down")]
    [string]$Action = "up",

    [Parameter(Position = 1)]
    [string]$Distro = "Ubuntu-26.04",

    [string]$Name = "",

    [string]$UserName = "aziz0220",

    [Security.SecureString]$LinuxPassword,

    [string]$InstallLocation = "",

    [string]$ExportPath = "",

    [switch]$WebDownload,

    [switch]$Force,

    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:InstallUrl = "https://raw.githubusercontent.com/aziz0220/dotfiles/main/install"
$script:WslExecutable = if ($env:DOTFILES_WSL_EXE) { $env:DOTFILES_WSL_EXE } else { "wsl.exe" }
$script:WslCommandRunner = $null

function Write-Stage {
    param([string]$Message)

    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Assert-WslName {
    param(
        [string]$Value,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "$Label must start with an alphanumeric character and contain only letters, numbers, dots, underscores, or hyphens."
    }
}

function Assert-LinuxUserName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
        throw "Linux user name '$Value' is invalid. Use 1-32 lowercase letters, numbers, underscores, or hyphens."
    }
}

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$Interactive,

        [switch]$AllowFailure
    )

    if ($null -ne $script:WslCommandRunner) {
        $result = & $script:WslCommandRunner $Arguments ([bool]$Interactive) ([bool]$AllowFailure)
    }
    elseif ($Interactive) {
        & $script:WslExecutable @Arguments
        $result = [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = @()
        }
    }
    else {
        $output = @(& $script:WslExecutable @Arguments 2>&1)
        $result = [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
        }
    }

    if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
        $detail = if ($result.Output.Count -gt 0) { ": $($result.Output -join [Environment]::NewLine)" } else { "" }
        throw "wsl.exe $($Arguments -join ' ') failed with exit code $($result.ExitCode)$detail"
    }

    return $result
}

function Get-RegisteredWslDistributions {
    $result = Invoke-WslCommand -Arguments @("--list", "--quiet")
    return @($result.Output | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-WslDistributionRegistered {
    param([string]$Name)

    return @(
        Get-RegisteredWslDistributions |
            Where-Object { [string]::Equals($_, $Name, [StringComparison]::OrdinalIgnoreCase) }
    ).Count -gt 0
}

function Test-LinuxUser {
    param(
        [string]$Name,
        [string]$UserName
    )

    $result = Invoke-WslCommand `
        -Arguments @("-d", $Name, "-u", "root", "--cd", "/", "--", "id", "-u", $UserName) `
        -AllowFailure
    return $result.ExitCode -eq 0
}

function Invoke-WslRootScript {
    param(
        [string]$Name,
        [string]$Script,
        [switch]$AllowFailure
    )

    return Invoke-WslCommand `
        -Arguments @("-d", $Name, "-u", "root", "--cd", "/", "--", "bash", "-lc", $Script) `
        -AllowFailure:$AllowFailure
}

function Initialize-WslUser {
    param(
        [string]$Name,
        [string]$UserName
    )

    $scriptBody = @'
set -euo pipefail
username='__USER__'
export DEBIAN_FRONTEND=noninteractive

if ! command -v sudo >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq sudo curl ca-certificates
fi

if ! id -u "$username" >/dev/null 2>&1; then
  useradd -m -U -s /bin/bash "$username"
fi

usermod -aG sudo "$username"
sudoers_file="/etc/sudoers.d/99-dotfiles-bootstrap-$username"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$username" > "$sudoers_file"
chmod 0440 "$sudoers_file"
visudo -cf "$sudoers_file" >/dev/null
'@.Replace("__USER__", $UserName)

    Invoke-WslRootScript -Name $Name -Script $scriptBody | Out-Null
}

function ConvertFrom-SecureStringPlainText {
    param([Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Read-NewLinuxPassword {
    param([string]$UserName)

    $first = Read-Host "New Linux password for $UserName" -AsSecureString
    $second = Read-Host "Confirm Linux password" -AsSecureString
    $firstPlain = ConvertFrom-SecureStringPlainText $first
    $secondPlain = ConvertFrom-SecureStringPlainText $second

    try {
        if ([string]::IsNullOrEmpty($firstPlain)) {
            throw "The Linux password cannot be empty."
        }
        if ($firstPlain -cne $secondPlain) {
            throw "The Linux passwords did not match. Rerun the command and try again."
        }
    }
    finally {
        $firstPlain = $null
        $secondPlain = $null
    }

    return $first
}

function Set-LinuxUserPassword {
    param(
        [string]$Name,
        [string]$UserName,
        [Security.SecureString]$Password
    )

    $plainText = ConvertFrom-SecureStringPlainText $Password
    $previousOutputEncoding = $global:OutputEncoding
    try {
        if ($plainText -match "[`r`n`0]") {
            throw "The Linux password cannot contain a newline or null character."
        }

        $global:OutputEncoding = [Text.UTF8Encoding]::new($false)
        "$UserName`:$plainText" | & $script:WslExecutable -d $Name -u root --cd / -- chpasswd
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set the Linux password for '$UserName'."
        }
    }
    finally {
        $global:OutputEncoding = $previousOutputEncoding
        $plainText = $null
    }
}

function Remove-BootstrapSudo {
    param(
        [string]$Name,
        [string]$UserName
    )

    $cleanup = "rm -f /etc/sudoers.d/99-dotfiles-bootstrap-$UserName"
    Invoke-WslRootScript -Name $Name -Script $cleanup -AllowFailure | Out-Null
}

function Set-WslDefaultUser {
    param(
        [string]$Name,
        [string]$UserName
    )

    $scriptBody = @'
set -euo pipefail
username='__USER__'
config=/etc/wsl.conf
tmp="$(mktemp)"
touch "$config"

if command -v zsh >/dev/null 2>&1; then
  usermod -s "$(command -v zsh)" "$username"
fi

awk -v wanted="$username" '
  BEGIN { in_user = 0; saw_user = 0; wrote_default = 0 }
  /^\[[^]]+\][[:space:]]*$/ {
    if (in_user && !wrote_default) {
      print "default=" wanted
      wrote_default = 1
    }
    in_user = ($0 ~ /^\[user\][[:space:]]*$/)
    if (in_user) saw_user = 1
    print
    next
  }
  in_user && /^[[:space:]]*default[[:space:]]*=/ {
    if (!wrote_default) {
      print "default=" wanted
      wrote_default = 1
    }
    next
  }
  { print }
  END {
    if (in_user && !wrote_default) print "default=" wanted
    if (!saw_user) {
      print ""
      print "[user]"
      print "default=" wanted
    }
  }
' "$config" > "$tmp"

install -o root -g root -m 0644 "$tmp" "$config"
rm -f "$tmp"
'@.Replace("__USER__", $UserName)

    Invoke-WslRootScript -Name $Name -Script $scriptBody | Out-Null
}

function Invoke-WslBootstrap {
    param(
        [string]$Name,
        [string]$UserName
    )

    $command = "set -euo pipefail; bash <(curl -fsSL '$script:InstallUrl')"
    Invoke-WslCommand `
        -Arguments @("-d", $Name, "-u", $UserName, "--cd", "~", "--", "bash", "-lc", $command) `
        -Interactive | Out-Null
}

function Invoke-WslValidation {
    param(
        [string]$Name,
        [string]$UserName
    )

    $command = 'set -euo pipefail; cd "$HOME/dotfiles"; ./scripts/validate_setup.sh'
    Invoke-WslCommand `
        -Arguments @("-d", $Name, "-u", $UserName, "--cd", "~", "--", "bash", "-lc", $command) `
        -Interactive | Out-Null
}

function Install-WslDistribution {
    param(
        [string]$Distro,
        [string]$Name,
        [string]$InstallLocation,
        [switch]$WebDownload
    )

    $online = Invoke-WslCommand -Arguments @("--list", "--online")
    $distributionPattern = '^\s*' + [regex]::Escape($Distro) + '(?:\s{2,}.*)?\s*$'
    if (@($online.Output | Where-Object { $_ -match $distributionPattern }).Count -eq 0) {
        throw "WSL distribution '$Distro' is not available. Run 'wsl --list --online' to see valid names."
    }

    $arguments = [System.Collections.Generic.List[string]]::new()
    @("--install", "--distribution", $Distro, "--name", $Name, "--no-launch") |
        ForEach-Object { $arguments.Add($_) }

    if ($WebDownload) {
        $arguments.Add("--web-download")
    }
    if (-not [string]::IsNullOrWhiteSpace($InstallLocation)) {
        $arguments.Add("--location")
        $arguments.Add([IO.Path]::GetFullPath($InstallLocation))
    }

    Invoke-WslCommand -Arguments $arguments.ToArray() -Interactive | Out-Null

    if (-not (Test-WslDistributionRegistered -Name $Name)) {
        throw "WSL did not register '$Name'. Rerun the same command; reboot first if Windows requested it."
    }

    Invoke-WslCommand -Arguments @("--set-version", $Name, "2") -Interactive | Out-Null
}

function Invoke-WslUp {
    param(
        [string]$Distro,
        [string]$Name,
        [string]$UserName,
        [Security.SecureString]$LinuxPassword,
        [string]$InstallLocation = "",
        [switch]$WebDownload,
        [switch]$NoLaunch
    )

    Assert-WslName -Value $Distro -Label "Distribution"
    Assert-WslName -Value $Name -Label "Instance name"
    Assert-LinuxUserName -Value $UserName

    if (-not (Test-WslDistributionRegistered -Name $Name)) {
        Write-Stage "Installing WSL2 distro '$Distro' as '$Name'"
        Install-WslDistribution `
            -Distro $Distro `
            -Name $Name `
            -InstallLocation $InstallLocation `
            -WebDownload:$WebDownload
    }
    else {
        Write-Host "Using existing WSL distro '$Name'."
    }

    $newUser = -not (Test-LinuxUser -Name $Name -UserName $UserName)
    Write-Stage "Preparing Linux user '$UserName'"

    try {
        Initialize-WslUser -Name $Name -UserName $UserName

        if ($newUser) {
            if ($null -eq $LinuxPassword) {
                $LinuxPassword = Read-NewLinuxPassword -UserName $UserName
            }
            Set-LinuxUserPassword -Name $Name -UserName $UserName -Password $LinuxPassword
        }

        Write-Stage "Bootstrapping '$Name'"
        Invoke-WslBootstrap -Name $Name -UserName $UserName

        Write-Stage "Validating '$Name'"
        Invoke-WslValidation -Name $Name -UserName $UserName

        Set-WslDefaultUser -Name $Name -UserName $UserName
    }
    finally {
        Remove-BootstrapSudo -Name $Name -UserName $UserName
    }

    Invoke-WslCommand -Arguments @("--terminate", $Name) -AllowFailure | Out-Null
    Write-Host "`nWSL distro '$Name' is fully bootstrapped and validated." -ForegroundColor Green

    if (-not $NoLaunch) {
        Write-Host "Launching '$Name' as '$UserName'..."
        Invoke-WslCommand -Arguments @("-d", $Name, "--cd", "~") -Interactive | Out-Null
    }
}

function Invoke-WslDown {
    param(
        [string]$Name,
        [string]$ExportPath = "",
        [switch]$Force
    )

    Assert-WslName -Value $Name -Label "Instance name"

    if (-not (Test-WslDistributionRegistered -Name $Name)) {
        Write-Host "WSL distro '$Name' is already absent."
        return
    }

    if (-not $Force) {
        Write-Warning "Unregistering '$Name' permanently deletes its filesystem, packages, and unpushed work."
        $confirmation = Read-Host "Type '$Name' to continue"
        if ($confirmation -cne $Name) {
            Write-Host "Cancelled."
            return
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
        $resolvedExportPath = [IO.Path]::GetFullPath($ExportPath)
        if (Test-Path -LiteralPath $resolvedExportPath) {
            throw "Export path already exists: $resolvedExportPath"
        }

        $exportDirectory = Split-Path -Parent $resolvedExportPath
        if (-not [string]::IsNullOrWhiteSpace($exportDirectory)) {
            New-Item -ItemType Directory -Path $exportDirectory -Force | Out-Null
        }

        Write-Stage "Exporting '$Name' to '$resolvedExportPath'"
        Invoke-WslCommand -Arguments @("--export", $Name, $resolvedExportPath) -Interactive | Out-Null
    }

    Write-Stage "Removing WSL distro '$Name'"
    Invoke-WslCommand -Arguments @("--terminate", $Name) -AllowFailure | Out-Null
    Invoke-WslCommand -Arguments @("--unregister", $Name) -Interactive | Out-Null

    if (Test-WslDistributionRegistered -Name $Name) {
        throw "WSL still reports '$Name' as registered after unregister completed."
    }

    Write-Host "WSL distro '$Name' was removed." -ForegroundColor Green
}

function Invoke-DotfilesWsl {
    param(
        [string]$Action,
        [string]$Distro,
        [string]$Name,
        [string]$UserName,
        [Security.SecureString]$LinuxPassword,
        [string]$InstallLocation,
        [string]$ExportPath,
        [switch]$WebDownload,
        [switch]$Force,
        [switch]$NoLaunch
    )

    if ($env:OS -ne "Windows_NT") {
        throw "Run this command from Windows PowerShell, not from inside Linux."
    }
    if (-not (Get-Command $script:WslExecutable -ErrorAction SilentlyContinue)) {
        throw "wsl.exe is unavailable. Install or update WSL first: wsl --install"
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = "$Distro-Dotfiles"
    }
    if ([string]::IsNullOrWhiteSpace($UserName)) {
        $UserName = $env:USERNAME.ToLowerInvariant()
    }

    if ($Action -eq "up") {
        Invoke-WslUp `
            -Distro $Distro `
            -Name $Name `
            -UserName $UserName `
            -LinuxPassword $LinuxPassword `
            -InstallLocation $InstallLocation `
            -WebDownload:$WebDownload `
            -NoLaunch:$NoLaunch
        return
    }

    Invoke-WslDown -Name $Name -ExportPath $ExportPath -Force:$Force
}

if ($env:DOTFILES_WSL_TESTING -ne "1") {
    Invoke-DotfilesWsl `
        -Action $Action `
        -Distro $Distro `
        -Name $Name `
        -UserName $UserName `
        -LinuxPassword $LinuxPassword `
        -InstallLocation $InstallLocation `
        -ExportPath $ExportPath `
        -WebDownload:$WebDownload `
        -Force:$Force `
        -NoLaunch:$NoLaunch
}
