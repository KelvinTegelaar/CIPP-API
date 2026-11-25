# Pester tests for when Invoke-CIPPOffboardingJob saves the offboarding snapshot: once, on a full
# run that strips groups, licences or roles, and never in a way that can stop the offboarding.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-Information { param($MessageData) }
    function Save-CIPPOffboardingSnapshot { param($TenantFilter, $UserID, $Username, $APIName, $Headers) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOffboardingJob.ps1')
}

Describe 'Invoke-CIPPOffboardingJob offboarding snapshot' {
    BeforeEach {
        $script:Order = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogMessage { }
        Mock Write-Information { }
        Mock Get-CIPPTextReplacement { $Text }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'user-id-1'; displayName = 'Pat Lee' } }
        Mock Start-CIPPOrchestrator { $script:Order.Add('orchestrator'); 'orch-1' }
        Mock Save-CIPPOffboardingSnapshot { $script:Order.Add('snapshot'); $true }
    }

    It 'saves the snapshot once, before the tasks start, when <Option> is selected' -ForEach @(
        @{ Option = 'RemoveGroups' }
        @{ Option = 'RemoveLicenses' }
        @{ Option = 'RemoveRoles' }
    ) {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ RevokeSessions = $true; $Option = $true })

        Should -Invoke Save-CIPPOffboardingSnapshot -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $UserID -eq 'user-id-1' -and $Username -eq 'pat@contoso.com' }
        $script:Order | Should -Be @('snapshot', 'orchestrator')
    }

    It 'saves the snapshot when licences are removed after a OneDrive copy' {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ RemoveLicenses = $true; OneDriveCopyTo = @('sam@contoso.com') })

        Should -Invoke Save-CIPPOffboardingSnapshot -Times 1 -Exactly
    }

    It 'skips the snapshot when no group, licence or role removal is selected' {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ RevokeSessions = $true; DisableSignIn = $true; ConvertToShared = $true })

        Should -Invoke Save-CIPPOffboardingSnapshot -Times 0 -Exactly
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly
    }

    It 'skips the snapshot on a step re-run' {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ RevokeSessions = $true; RemoveGroups = $true; RemoveLicenses = $true }) -StepIndexes @(1)

        Should -Invoke Save-CIPPOffboardingSnapshot -Times 0 -Exactly
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly
    }

    It 'skips the snapshot when the user is being deleted, since the removals are skipped too' {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ DeleteUser = $true; RemoveGroups = $true; RemoveLicenses = $true })

        Should -Invoke Save-CIPPOffboardingSnapshot -Times 0 -Exactly
    }

    It 'still starts the offboarding when the snapshot throws' {
        Mock Save-CIPPOffboardingSnapshot { throw 'storage is down' }

        $Result = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ RemoveGroups = $true })

        $Result | Should -BeLike 'Offboarding job started*'
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly
    }
}
