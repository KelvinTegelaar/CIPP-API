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
    function Start-CIPPBaselineOrchestrator { param($TenantFilter, $StandardName, $Mode, $TriggeredBy) }

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

Describe 'Push-CIPPBaselineCacheRefresh verification' {
    BeforeEach {
        Mock Start-CIPPOrchestrator { }
        Mock Start-CIPPBaselineOrchestrator { }
        Mock Set-CIPPBaselineTrendPoint { }
        Mock Write-LogMessage { }
        Mock Get-CIPPBaselineCommand { if ($Name -in @('Set-CIPPDBCacheIntunePolicies', 'Set-CIPPDBCacheGroups')) { $Name } }
    }

    It 'chains one verification per tenant, each remediated standard once' {
        $Item = [pscustomobject]@{
            Parameters = @{ RunId = 'run-1' }
            Results    = @(
                @(
                    [pscustomobject]@{ TenantFilter = 'contoso.com'; CacheType = 'IntunePolicies'; Standard = 'IntuneTemplate#a' }
                    [pscustomobject]@{ TenantFilter = 'contoso.com'; CacheType = 'IntuneDeviceConfigurations'; Standard = 'IntuneTemplate#a' }
                )
                @([pscustomobject]@{ TenantFilter = 'contoso.com'; CacheType = 'IntunePolicies'; Standard = 'IntuneTemplate#b' })
                @([pscustomobject]@{ TenantFilter = 'fabrikam.com'; CacheType = 'Groups'; Standard = 'GroupTemplate#c' })
            )
        }

        Push-CIPPBaselineCacheRefresh -Item $Item

        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter {
            $Verify = @($InputObject.PostExecution.Parameters.Verify)
            $Contoso = $Verify.Where({ $_.TenantFilter -eq 'contoso.com' })[0]
            $InputObject.PostExecution.FunctionName -eq 'CIPPBaselineCacheRefresh' -and $Verify.Count -eq 2 -and
            (@($Contoso.Standards | Sort-Object) -join ',') -eq 'IntuneTemplate#a,IntuneTemplate#b'
        }
    }

    It 'attaches no verification when the records carry no standard' {
        $Item = [pscustomobject]@{
            Parameters = @{ RunId = 'run-1' }
            Results    = @([pscustomobject]@{ TenantFilter = 'contoso.com'; CacheType = 'IntunePolicies' })
        }

        Push-CIPPBaselineCacheRefresh -Item $Item

        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter { -not $InputObject.PostExecution }
    }

    It 'the refresh post-exec starts a compare per tenant and nothing else' {
        $Item = [pscustomobject]@{
            Parameters = @{
                RunId  = 'run-1'
                Verify = @(
                    @{ TenantFilter = 'contoso.com'; Standards = @('IntuneTemplate#a', 'IntuneTemplate#b') }
                    @{ TenantFilter = 'fabrikam.com'; Standards = @('GroupTemplate#c') }
                )
            }
            Results    = @([pscustomobject]@{ TenantFilter = 'contoso.com'; CacheType = 'IntunePolicies' })
        }

        Push-CIPPBaselineCacheRefresh -Item $Item

        Should -Invoke Start-CIPPBaselineOrchestrator -Times 2 -Exactly
        Should -Invoke Start-CIPPBaselineOrchestrator -Times 1 -Exactly -ParameterFilter {
            $TenantFilter -eq 'contoso.com' -and $Mode -eq 'compare' -and $TriggeredBy -eq 'verification' -and
            (@($StandardName) -join ',') -eq 'IntuneTemplate#a,IntuneTemplate#b'
        }
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        Should -Invoke Set-CIPPBaselineTrendPoint -Times 0 -Exactly
    }
}
