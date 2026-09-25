# Pester tests for Clear-CIPPImmutableId.
#
# Thin wrapper kept for the offboarding job and the delta-query scheduled task that persists its name.
# It decides whether to clear now or schedule for after deletion, and delegates the clear itself to
# Clear-CIPPOnPremisesAttributes with the immutable ID only.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Clear-CIPPImmutableId.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Clear-CIPPImmutableId.ps1 at $FunctionPath" }

    function Clear-CIPPOnPremisesAttributes { param($TenantFilter, $UserID, $Username, $Headers, $APIName, $Attributes) }
    function Write-LogMessage { param($headers, $API, $APIName, $tenant, $TenantFilter, $message, $Sev, $Severity, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Add-CIPPScheduledTask { param($Task, $hidden, $DisallowDuplicateName) }

    . $FunctionPath
}

Describe 'Clear-CIPPImmutableId' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPScheduledTask -MockWith { }
        Mock -CommandName Clear-CIPPOnPremisesAttributes -MockWith { "cleared $($Attributes -join ',')" }
    }

    It 'delegates to the shared helper with the immutable ID only' {
        $Result = Clear-CIPPImmutableId -UserID 'user-guid' -TenantFilter 'contoso.com' -Username 'ada@contoso.com'

        $Result | Should -Be 'cleared onPremisesImmutableId'
        Should -Invoke Clear-CIPPOnPremisesAttributes -Times 1 -ParameterFilter {
            $UserID -eq 'user-guid' -and $TenantFilter -eq 'contoso.com' -and $Username -eq 'ada@contoso.com' -and
            @($Attributes).Count -eq 1 -and @($Attributes)[0] -eq 'onPremisesImmutableId'
        }
    }

    It 'clears immediately when the user object is cloud-only with an immutable ID' {
        $User = [pscustomobject]@{ onPremisesSyncEnabled = $false; onPremisesImmutableId = 'AbCd==' }

        Clear-CIPPImmutableId -UserID 'user-guid' -TenantFilter 'contoso.com' -User $User

        Should -Invoke Clear-CIPPOnPremisesAttributes -Times 1
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'schedules a delta-query task instead of clearing when the user is still synced' {
        $User = [pscustomobject]@{ onPremisesSyncEnabled = $true; onPremisesImmutableId = 'AbCd==' }

        $Result = Clear-CIPPImmutableId -UserID 'user-guid' -TenantFilter 'contoso.com' -User $User -Username 'ada@contoso.com'

        $Result | Should -Match 'Scheduled'
        Should -Invoke Add-CIPPScheduledTask -Times 1 -ParameterFilter {
            $Task.Command.value -eq 'Clear-CIPPImmutableID' -and $Task.Trigger.EventType -eq 'deleted' -and $Task.Parameters.UserID -eq 'user-guid'
        }
        Should -Invoke Clear-CIPPOnPremisesAttributes -Times 0
    }

    It 'does nothing when the user object has no immutable ID' {
        $User = [pscustomobject]@{ onPremisesSyncEnabled = $false; onPremisesImmutableId = $null }

        $Result = Clear-CIPPImmutableId -UserID 'user-guid' -TenantFilter 'contoso.com' -User $User

        $Result | Should -Match 'does not have an ImmutableID'
        Should -Invoke Clear-CIPPOnPremisesAttributes -Times 0
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }
}
