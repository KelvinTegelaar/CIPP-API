# Pester tests for Push-CIPPBaselineCacheRefresh: only cache types with their own collector are queued.
# Family types such as IntuneDeviceConfigurations are written by the IntunePolicies umbrella collector,
# so queueing them by name failed with "Function Set-CIPPDBCache<Type> does not exist".

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-CIPPBaselineCacheRefresh.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function Set-CippBaselineRunContext { param($RunId) }
    function Set-CIPPBaselineTrendPoint { }
    function Send-CIPPBaselineAlertDigest { }
    function New-CippQueueEntry { param($Name, $TotalTasks) [pscustomobject]@{ RowKey = 'queue-1' } }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }
    function Get-CIPPBaselineCommand { param($Name) }

    . $FunctionPath
}

Describe 'Push-CIPPBaselineCacheRefresh' {
    BeforeEach {
        Mock Start-CIPPOrchestrator { }
        Mock Write-LogMessage { }
        Mock Get-CIPPBaselineCommand { if ($Name -eq 'Set-CIPPDBCacheIntunePolicies') { 'Set-CIPPDBCacheIntunePolicies' } }
    }

    It 'queues the umbrella collector and skips family types without a collector' {
        $Item = [pscustomobject]@{
            Parameters = @{ RunId = 'run-1' }
            Results    = @(
                @(
                    [pscustomobject]@{ TenantFilter = 'contoso.com'; CacheType = 'IntunePolicies' }
                    [pscustomobject]@{ TenantFilter = 'contoso.com'; CacheType = 'IntuneDeviceConfigurations' }
                    [pscustomobject]@{ TenantFilter = 'contoso.com'; CacheType = 'IntuneMobileAppConfigurations' }
                )
            )
        }

        Push-CIPPBaselineCacheRefresh -Item $Item

        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter {
            @($InputObject.Batch).Count -eq 1 -and @($InputObject.Batch)[0].Name -eq 'IntunePolicies'
        }
    }

    It 'starts nothing when no remediated type has a collector' {
        $Item = [pscustomobject]@{
            Parameters = @{ RunId = 'run-1' }
            Results    = @([pscustomobject]@{ TenantFilter = 'contoso.com'; CacheType = 'IntuneDeviceConfigurations' })
        }

        Push-CIPPBaselineCacheRefresh -Item $Item

        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }
}
