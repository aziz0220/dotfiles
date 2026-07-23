$ErrorActionPreference = "Stop"
$env:DOTFILES_WSL_TESTING = "1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$lifecycleScript = Join-Path $repoRoot "scripts/wsl.ps1"

if (-not (Test-Path -LiteralPath $lifecycleScript)) {
    throw "Missing WSL lifecycle script: $lifecycleScript"
}

. $lifecycleScript

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }

    Assert-True $threw $Message
}

function Reset-WslMock {
    param(
        [bool]$Registered = $false,
        [string]$RegisteredName = "Dotfiles-Test",
        [bool]$OnlineAvailable = $true,
        [bool]$UserExists = $false,
        [bool]$FailBootstrap = $false
    )

    $script:MockRegistered = $Registered
    $script:MockRegisteredName = $RegisteredName
    $script:MockRegisteredNames = [System.Collections.Generic.List[string]]::new()
    if ($Registered) {
        $script:MockRegisteredNames.Add($RegisteredName)
    }
    $script:MockOnlineAvailable = $OnlineAvailable
    $script:MockUserExists = $UserExists
    $script:MockFailBootstrap = $FailBootstrap
    $script:MockCalls = [System.Collections.Generic.List[string]]::new()
    $script:PasswordSetCount = 0

    $script:WslCommandRunner = {
        param(
            [string[]]$Arguments,
            [bool]$Interactive,
            [bool]$AllowFailure
        )

        $call = $Arguments -join " "
        $script:MockCalls.Add($call)

        if ($Arguments.Count -ge 2 -and $Arguments[0] -eq "--list" -and $Arguments[1] -eq "--online") {
            $onlineDistributions = if ($script:MockOnlineAvailable) {
                @("Ubuntu-26.04                    Ubuntu 26.04 LTS")
            }
            else {
                @("Ubuntu-24.04                    Ubuntu 24.04 LTS")
            }
            return [pscustomobject]@{
                ExitCode = 0
                Output = @("NAME                            FRIENDLY NAME") + $onlineDistributions
            }
        }

        if ($Arguments.Count -ge 2 -and $Arguments[0] -eq "--list" -and $Arguments[1] -eq "--quiet") {
            $output = @($script:MockRegisteredNames)
            return [pscustomobject]@{ ExitCode = 0; Output = $output }
        }

        if ($Arguments.Count -gt 0 -and $Arguments[0] -eq "--install") {
            $script:MockRegistered = $true
            $nameIndex = [Array]::IndexOf($Arguments, "--name")
            if ($nameIndex -ge 0 -and ($nameIndex + 1) -lt $Arguments.Count) {
                $script:MockRegisteredName = $Arguments[$nameIndex + 1]
                if (-not $script:MockRegisteredNames.Contains($script:MockRegisteredName)) {
                    $script:MockRegisteredNames.Add($script:MockRegisteredName)
                }
            }
            return [pscustomobject]@{ ExitCode = 0; Output = @() }
        }

        if ($Arguments.Count -gt 1 -and $Arguments[0] -eq "--import") {
            $script:MockRegistered = $true
            $script:MockRegisteredName = $Arguments[1]
            if (-not $script:MockRegisteredNames.Contains($script:MockRegisteredName)) {
                $script:MockRegisteredNames.Add($script:MockRegisteredName)
            }
            return [pscustomobject]@{ ExitCode = 0; Output = @() }
        }

        if ($call -match "id -u tester") {
            $exitCode = if ($script:MockUserExists) { 0 } else { 1 }
            return [pscustomobject]@{ ExitCode = $exitCode; Output = @() }
        }

        if ($call -match "raw.githubusercontent.com/aziz0220/dotfiles/main/install") {
            $exitCode = if ($script:MockFailBootstrap) { 42 } else { 0 }
            return [pscustomobject]@{ ExitCode = $exitCode; Output = @() }
        }

        if ($Arguments.Count -gt 0 -and $Arguments[0] -eq "--unregister") {
            [void]$script:MockRegisteredNames.Remove($Arguments[1])
            $script:MockRegistered = $script:MockRegisteredNames.Count -gt 0
            return [pscustomobject]@{ ExitCode = 0; Output = @() }
        }

        return [pscustomobject]@{ ExitCode = 0; Output = @() }
    }
}

function Set-LinuxUserPassword {
    param(
        [string]$Name,
        [string]$UserName,
        [Security.SecureString]$Password
    )

    $script:PasswordSetCount++
}

function Test-Call {
    param([string]$Pattern)

    return @($script:MockCalls | Where-Object { $_ -match $Pattern }).Count -gt 0
}

$testPassword = ConvertTo-SecureString "test-password" -AsPlainText -Force

Reset-WslMock
Invoke-WslUp `
    -Distro "Ubuntu-26.04" `
    -Name "Dotfiles-Test" `
    -UserName "tester" `
    -LinuxPassword $testPassword `
    -NoLaunch

Assert-True (Test-Call '^--install --distribution Ubuntu-26\.04 --name Dotfiles-Test --no-launch$') "fresh up should install the requested named distro"
Assert-True (Test-Call '^--set-version Dotfiles-Test 2$') "fresh up should configure only the named instance as WSL2"
Assert-True (-not (Test-Call '^--install .*--version ')) "fresh up should not pass the unsupported --version option to wsl --install"
Assert-True (Test-Call 'raw\.githubusercontent\.com/aziz0220/dotfiles/main/install') "fresh up should run the repository bootstrap"
Assert-True (Test-Call 'scripts/validate_setup\.sh') "fresh up should run post-bootstrap validation"
Assert-True (Test-Call 'usermod -s .*zsh') "fresh up should make zsh the completed user's login shell"
Assert-True (Test-Call '^--terminate Dotfiles-Test$') "fresh up should terminate once so wsl.conf takes effect"
Assert-True ($script:PasswordSetCount -eq 1) "fresh up should set the new Linux user's password"
Assert-True $script:MockRegistered "fresh up should leave the distro registered"

Reset-WslMock -Registered $true -UserExists $true
Invoke-WslUp `
    -Distro "Ubuntu-26.04" `
    -Name "Dotfiles-Test" `
    -UserName "tester" `
    -NoLaunch

Assert-True (-not (Test-Call '^--install ')) "idempotent up should not reinstall an existing distro"
Assert-True ($script:PasswordSetCount -eq 0) "idempotent up should not reset an existing user's password"
Assert-True (Test-Call 'scripts/validate_setup\.sh') "idempotent up should still validate the distro"

Reset-WslMock -Registered $true -UserExists $true -FailBootstrap $true
Assert-Throws {
    Invoke-WslUp `
        -Distro "Ubuntu-26.04" `
        -Name "Dotfiles-Test" `
        -UserName "tester" `
        -NoLaunch
} "bootstrap failure should fail the up action"
Assert-True (Test-Call 'rm -f /etc/sudoers\.d/99-dotfiles-bootstrap-tester') "bootstrap failure should remove temporary passwordless sudo"

Reset-WslMock -Registered $true -UserExists $true
$exportPath = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-wsl-test.tar"
Invoke-WslDown -Name "Dotfiles-Test" -ExportPath $exportPath -Force
Assert-True (Test-Call '^--export Dotfiles-Test .*dotfiles-wsl-test\.tar$') "down should export when a backup path is supplied"
Assert-True (Test-Call '^--unregister Dotfiles-Test$') "down should unregister the requested distro"
Assert-True (-not $script:MockRegistered) "down should leave the distro unregistered"

Reset-WslMock
Invoke-WslDown -Name "Dotfiles-Test" -Force
Assert-True (-not (Test-Call '^--unregister ')) "down should be idempotent when the distro is already absent"

function Read-Host {
    param(
        [string]$Prompt,
        [switch]$AsSecureString
    )

    return "cancelled"
}

Reset-WslMock -Registered $true -UserExists $true
Invoke-WslDown -Name "Dotfiles-Test"
Assert-True (-not (Test-Call '^--unregister ')) "down should not unregister without exact confirmation"

Reset-WslMock
Assert-Throws {
    Invoke-WslUp `
        -Distro "Debian" `
        -Name "Dotfiles-Test" `
        -UserName "tester" `
        -LinuxPassword $testPassword `
        -NoLaunch
} "up should reject a distro that is absent from the online catalog"
Assert-True (-not (Test-Call '^--install ')) "unavailable distro should fail before install"

$cloneLocation = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-wsl-clone-test"
Reset-WslMock -Registered $true -RegisteredName "Ubuntu-26.04" -OnlineAvailable $false -UserExists $true
Invoke-WslUp `
    -Distro "Ubuntu-26.04" `
    -Name "Dotfiles-Test" `
    -UserName "tester" `
    -InstallLocation $cloneLocation `
    -NoLaunch
Assert-True (Test-Call '^--export Ubuntu-26\.04 .*\.tar$') "catalog miss should export the existing source distro"
Assert-True (Test-Call ('^--import Dotfiles-Test ' + [regex]::Escape([IO.Path]::GetFullPath($cloneLocation)) + ' .*\.tar --version 2$')) "catalog miss should import a separate WSL2 instance"
Assert-True (-not (Test-Call '^--unregister Ubuntu-26\.04$')) "local clone fallback should not unregister the source distro"
Assert-True $script:MockRegisteredNames.Contains("Ubuntu-26.04") "local clone fallback should preserve the source registration"
Assert-True $script:MockRegisteredNames.Contains("Dotfiles-Test") "local clone fallback should register the managed instance"
Assert-True (Test-Call '^-d Dotfiles-Test ') "local clone fallback should bootstrap only the managed instance"

$defaultCloneRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "WSL"
$defaultCloneLocation = Get-WslImportLocation -Name "Dotfiles-Test" -InstallLocation ""
Assert-True ($defaultCloneLocation -eq (Join-Path $defaultCloneRoot "Dotfiles-Test")) "local clone fallback should have a safe default install location"

Reset-WslMock -Registered $true -UserExists $true
Assert-Throws {
    Invoke-WslUp `
        -Distro "Ubuntu-26.04" `
        -Name "Dotfiles-Test" `
        -UserName "Bad User" `
        -NoLaunch
} "up should reject unsafe Linux usernames"

Assert-Throws {
    Invoke-WslDown -Name "Bad Name" -Force
} "down should reject unsafe WSL instance names"

$previousOs = $env:OS
$previousWslExecutable = $script:WslExecutable
try {
    $env:OS = "Windows_NT"
    $script:WslExecutable = (Get-Process -Id $PID).Path
    Reset-WslMock -Registered $true -RegisteredName "Ubuntu-26.04" -UserExists $true
    Invoke-DotfilesWsl `
        -Action "up" `
        -Distro "Ubuntu-26.04" `
        -Name "" `
        -UserName "tester" `
        -LinuxPassword $testPassword `
        -InstallLocation "" `
        -ExportPath "" `
        -NoLaunch
    Assert-True (Test-Call '^--install --distribution Ubuntu-26\.04 --name Ubuntu-26\.04-Dotfiles --no-launch$') "default up should install a separate managed instance"
    Assert-True (Test-Call '^-d Ubuntu-26\.04-Dotfiles ') "default up should operate only on the managed instance"
}
finally {
    $env:OS = $previousOs
    $script:WslExecutable = $previousWslExecutable
}

Write-Host "PASS: WSL lifecycle handling"
