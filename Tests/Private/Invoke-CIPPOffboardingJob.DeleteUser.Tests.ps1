# Pester tests for the DeleteUser guard in Invoke-CIPPOffboardingJob:
# - When DeleteUser is true, only Remove-CIPPUser and Set-CIPPSharePointPerms may run
# - When DeleteUser is false/absent, other selected tasks still run

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $JobPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOffboardingJob.ps1'
    $HtmlPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'
    if (-not (Test-Path $JobPath)) { throw "Could not locate Invoke-CIPPOffboardingJob.ps1 at $JobPath" }
    if (-not (Test-Path $HtmlPath)) { throw "Could not locate Test-CIPPHtmlIsEmpty.ps1 at $HtmlPath" }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-Information { param($MessageData) }

    . $HtmlPath
    . $JobPath
}

Describe 'Invoke-CIPPOffboardingJob DeleteUser guard' {
    BeforeEach {
        $script:CapturedInput = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-Information -MockWith { }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id                    = 'user-id-1'
                displayName           = 'Pat Lee'
                onPremisesSyncEnabled = $false
                onPremisesImmutableId = $null
            }
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith {
            $script:CapturedInput = $InputObject
            'orch-1'
        }
    }

    It 'only runs Remove-CIPPUser and Set-CIPPSharePointPerms when DeleteUser is true' {
        $Options = [pscustomobject]@{
            DeleteUser       = $true
            ConvertToShared  = $true
            RemoveLicenses   = $true
            RevokeSessions   = $true
            HideFromGAL      = $true
            RemoveMFADevices = $true
            OnedriveAccess   = @(@{ value = 'helper-id-1' })
        }

        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options $Options

        $script:CapturedInput.Batch | Should -Not -BeNullOrEmpty
        $Cmdlets = $script:CapturedInput.Batch | ForEach-Object { $_.Cmdlet } | Sort-Object -Unique
        $Cmdlets | Should -Be @('Remove-CIPPUser', 'Set-CIPPSharePointPerms')
    }

    It 'runs other selected tasks when DeleteUser is false' {
        $Options = [pscustomobject]@{
            DeleteUser      = $false
            ConvertToShared = $true
            RemoveLicenses  = $true
            RevokeSessions  = $true
        }

        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options $Options

        $Cmdlets = $script:CapturedInput.Batch | ForEach-Object { $_.Cmdlet } | Sort-Object -Unique
        $Cmdlets | Should -Contain 'Set-CIPPMailboxType'
        $Cmdlets | Should -Contain 'Remove-CIPPLicense'
        $Cmdlets | Should -Contain 'Revoke-CIPPSessions'
        $Cmdlets | Should -Not -Contain 'Remove-CIPPUser'
    }
}
