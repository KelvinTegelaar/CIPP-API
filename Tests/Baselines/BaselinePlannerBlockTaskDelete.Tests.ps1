# PlannerBlockTaskDelete: the collector caches each Planner-licensed enabled member's UserPolicy,
# the hook grades the cached rows (narrowed by group names), and the executor PUTs the block for
# each offender behind the shared 24h rerun guard.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Test-CIPPBaselineCacheCollected { param($TenantFilter, $Type) }
    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type, $CollectorType, $CollectorArgs) }
    function New-GraphBulkRequest { param($tenantid, $Requests, $asapp, $Version, $scope) }
    function New-GraphGetRequest { param($uri, $tenantid, $scope, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type, $scope, $AsApp) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Test-CIPPRerun { param($TenantFilter, $Type, $API, $Settings, [int64]$Interval) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }
    function Get-NormalizedError { param($Message) $Message }
    . (Join-Path $script:RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCachePlannerUserPolicies.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/PrepareHooks/Get-CIPPBaselinePlannerBlockTaskDeleteState.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Executors/Invoke-CIPPBaselinePlannerBlockTaskDelete.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Groups = @([PSCustomObject]@{ id = 'grp-ops'; displayName = 'Ops' })

    function Invoke-Hook {
        param($Variables = [PSCustomObject]@{})
        Get-CIPPBaselinePlannerBlockTaskDeleteState -Item ([PSCustomObject]@{ Variables = $Variables }) -TenantFilter $script:Tenant
    }
}

Describe 'Set-CIPPDBCachePlannerUserPolicies' {
    BeforeEach {
        $Plan = [PSCustomObject]@{ servicePlanId = 'b737dad2-2f6c-4c65-90e3-ca563267e8b9'; capabilityStatus = 'Enabled' }
        $DisabledPlan = [PSCustomObject]@{ servicePlanId = 'b737dad2-2f6c-4c65-90e3-ca563267e8b9'; capabilityStatus = 'Deleted' }
        $script:Users = @(
            [PSCustomObject]@{ id = 'u-ann'; userPrincipalName = 'ann@contoso.com'; userType = 'Member'; accountEnabled = $true; assignedPlans = @($Plan) }
            [PSCustomObject]@{ id = 'u-ben'; userPrincipalName = 'ben@contoso.com'; userType = 'Member'; accountEnabled = $true; assignedPlans = @($Plan) }
            [PSCustomObject]@{ id = 'u-new'; userPrincipalName = "o'neil@contoso.com"; userType = 'Member'; accountEnabled = $true; assignedPlans = @($Plan) }
            [PSCustomObject]@{ id = 'u-off'; userPrincipalName = 'off@contoso.com'; userType = 'Member'; accountEnabled = $false; assignedPlans = @($Plan) }
            [PSCustomObject]@{ id = 'u-nolic'; userPrincipalName = 'nolic@contoso.com'; userType = 'Member'; accountEnabled = $true; assignedPlans = @($DisabledPlan) }
            [PSCustomObject]@{ id = 'u-guest'; userPrincipalName = 'guest@ext.com'; userType = 'Guest'; accountEnabled = $true; assignedPlans = @($Plan) }
        )
        $script:Policies = @{
            'ann@contoso.com' = [PSCustomObject]@{ blockDeleteTasksNotCreatedBySelf = $false }
            'ben@contoso.com' = [PSCustomObject]@{ blockDeleteTasksNotCreatedBySelf = $true }
        }
        $script:Written = $null
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem { $script:Written = @($Data) }
        Mock New-GraphGetRequest { $script:Users } -ParameterFilter { $uri -like 'https://graph.microsoft.com/*' }
        Mock New-GraphGetRequest {
            if ($uri -match "UserPolicy\('(.+)'\)$") {
                $Upn = $Matches[1] -replace "''", "'"
                if ($script:Policies.ContainsKey($Upn)) { return $script:Policies[$Upn] }
            }
            throw '403 Forbidden'
        }
    }

    It 'caches licensed enabled members only, recording a missing policy as not blocked' {
        Set-CIPPDBCachePlannerUserPolicies -TenantFilter $script:Tenant
        @($script:Written.userPrincipalName) | Should -Be @('ann@contoso.com', 'ben@contoso.com', "o'neil@contoso.com")
        @($script:Written.blockDeleteTasksNotCreatedBySelf) | Should -Be @($false, $true, $false)
        @($script:Written.policyExists) | Should -Be @($true, $true, $false)
        Should -Invoke Add-CIPPDbItem -ParameterFilter { $Type -eq 'PlannerUserPolicies' -and $AddCount -and $ClearOnEmpty } -Times 1 -Exactly
    }

    It 'reads each policy app-only on the tasks.office.com scope with the UPN quote-escaped' {
        Set-CIPPDBCachePlannerUserPolicies -TenantFilter $script:Tenant
        Should -Invoke New-GraphGetRequest -ParameterFilter {
            $uri -eq "https://tasks.office.com/taskAPI/tenantAdminSettings/UserPolicy('o''neil@contoso.com')" -and $scope -eq 'https://tasks.office.com/.default' -and $AsApp -eq $true
        } -Times 1 -Exactly
    }

    It 'skips a user whose read fails for a reason other than a missing policy, and warns' {
        $script:Policies['ann@contoso.com'] = '500'
        Mock New-GraphGetRequest {
            $Upn = ([regex]::Match($uri, "UserPolicy\('(.+)'\)$").Groups[1].Value) -replace "''", "'"
            if ($script:Policies[$Upn] -eq '500') { throw '500 Internal Server Error' }
            if ($script:Policies.ContainsKey($Upn)) { return $script:Policies[$Upn] }
            throw '403 Forbidden'
        } -ParameterFilter { $uri -like '*tasks.office.com*' }
        Set-CIPPDBCachePlannerUserPolicies -TenantFilter $script:Tenant
        @($script:Written.userPrincipalName) | Should -Be @('ben@contoso.com', "o'neil@contoso.com")
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*1 of 3*ann@contoso.com*' }
    }

    It 'writes nothing when every policy read fails, so an empty set never grades the tenant compliant' {
        Mock New-GraphGetRequest { throw '500 Internal Server Error' } -ParameterFilter { $uri -like '*tasks.office.com*' }
        Set-CIPPDBCachePlannerUserPolicies -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' -and $message -like '*every Planner user policy read failed*' }
    }

    It 'writes nothing when the user listing fails' {
        Mock New-GraphGetRequest { throw 'graph down' } -ParameterFilter { $uri -like 'https://graph.microsoft.com/*' }
        Set-CIPPDBCachePlannerUserPolicies -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 0
    }
}

Describe 'Get-CIPPBaselinePlannerBlockTaskDeleteState' {
    BeforeEach {
        $script:Rows = @(
            [PSCustomObject]@{ id = 'u-ann'; userPrincipalName = 'ann@contoso.com'; policyExists = $true; blockDeleteTasksNotCreatedBySelf = $false }
            [PSCustomObject]@{ id = 'u-ben'; userPrincipalName = 'ben@contoso.com'; policyExists = $true; blockDeleteTasksNotCreatedBySelf = $true }
            [PSCustomObject]@{ id = 'u-new'; userPrincipalName = "o'neil@contoso.com"; policyExists = $false; blockDeleteTasksNotCreatedBySelf = $false }
        )
        Mock New-CIPPDbRequest { $script:Rows }
        Mock Test-CIPPBaselineCacheCollected { $true }
        Mock Get-CIPPBaselineCacheRows { $script:Groups }
        Mock New-GraphBulkRequest { @() }
    }

    It 'flags every cached user whose policy does not block, reading only the PlannerUserPolicies cache' {
        $Prepared = Invoke-Hook
        @($Prepared.Current.offenders) | Should -Be @('ann@contoso.com', "o'neil@contoso.com")
        @($Prepared.Current.targets.userPrincipalName) | Should -Be @('ann@contoso.com', "o'neil@contoso.com")
        Should -Invoke New-CIPPDbRequest -ParameterFilter { $Type -eq 'PlannerUserPolicies' } -Times 1 -Exactly
        Should -Invoke New-GraphBulkRequest -Times 0
    }

    It 'grades a collected-but-empty cache as compliant' {
        Mock New-CIPPDbRequest { @() }
        @((Invoke-Hook).Current.offenders) | Should -HaveCount 0
        (Invoke-Hook).Current | Should -Not -BeNullOrEmpty
    }

    It 'returns No Data when the cache has never been collected' {
        Mock New-CIPPDbRequest { @() }
        Mock Test-CIPPBaselineCacheCollected { $false }
        (Invoke-Hook).Current | Should -BeNullOrEmpty
    }

    It 'restricts to include-group transitive members' {
        Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = 'include-grp-ops'; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'u-new' }) } }) }
        @((Invoke-Hook ([PSCustomObject]@{ includeGroups = @('Ops') })).Current.offenders) | Should -Be @("o'neil@contoso.com")
    }

    It 'removes exclude-group members, accepting {label, value} wrappers' {
        Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = 'exclude-grp-ops'; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'u-ann' }) } }) }
        @((Invoke-Hook ([PSCustomObject]@{ excludeGroups = @([PSCustomObject]@{ label = 'Ops'; value = 'Ops' }) })).Current.offenders) | Should -Be @("o'neil@contoso.com")
    }

    It 'returns No Data for an unresolvable group name' {
        (Invoke-Hook ([PSCustomObject]@{ excludeGroups = @('Missing') })).Current | Should -BeNullOrEmpty
        Should -Invoke New-GraphBulkRequest -Times 0
    }

    It 'returns No Data when a membership lookup fails' {
        Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = 'include-grp-ops'; status = 403; body = $null }) }
        (Invoke-Hook ([PSCustomObject]@{ includeGroups = @('Ops') })).Current | Should -BeNullOrEmpty
    }
}

Describe 'PlannerBlockTaskDelete definition' {
    It 'reads the PlannerUserPolicies cache with the 3h freshness pre-check' {
        $Definition = Get-Content -Raw (Join-Path $script:RepoRoot 'Config/BaselineStandards/Teams Standards/PlannerBlockTaskDelete.json') | ConvertFrom-Json
        $Definition.read.cacheType | Should -Be 'PlannerUserPolicies'
        @($Definition.read.requiredCaches) | Should -Contain 'PlannerUserPolicies'
    }
}

Describe 'Invoke-CIPPBaselinePlannerBlockTaskDelete' {
    BeforeEach {
        Mock Test-CIPPRerun { $false }
        Mock Write-LogMessage {}
        Mock New-GraphPOSTRequest {}
        $script:Current = [PSCustomObject]@{ targets = @([PSCustomObject]@{ userPrincipalName = 'ann@contoso.com' }, [PSCustomObject]@{ userPrincipalName = "o'neil@contoso.com" }) }
    }

    It 'PUTs the block app-only per target, on every run (no rerun guard)' {
        Invoke-CIPPBaselinePlannerBlockTaskDelete -Remediate @{} -TenantFilter 'contoso.onmicrosoft.com' -Current $script:Current
        Should -Invoke Test-CIPPRerun -Times 0
        Should -Invoke New-GraphPOSTRequest -ParameterFilter {
            $uri -eq "https://tasks.office.com/taskAPI/tenantAdminSettings/UserPolicy('o''neil@contoso.com')" -and $type -eq 'PUT' -and $AsApp -eq $true -and
            $scope -eq 'https://tasks.office.com/.default' -and $body -eq '{"blockDeleteTasksNotCreatedBySelf":true}'
        } -Times 1 -Exactly
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly
    }

    It 'is a no-op with nothing to write, and throws with no data at all' {
        Invoke-CIPPBaselinePlannerBlockTaskDelete -Remediate @{} -TenantFilter 'contoso.onmicrosoft.com' -Current ([PSCustomObject]@{ targets = @() })
        Should -Invoke New-GraphPOSTRequest -Times 0
        { Invoke-CIPPBaselinePlannerBlockTaskDelete -Remediate @{} -TenantFilter 'contoso.onmicrosoft.com' -Current $null } | Should -Throw '*no Planner policy data*'
    }

    It 'continues past a per-user failure without throwing' {
        Mock New-GraphPOSTRequest { throw 'boom' } -ParameterFilter { $uri -like "*ann@*" }
        { Invoke-CIPPBaselinePlannerBlockTaskDelete -Remediate @{} -TenantFilter 'contoso.onmicrosoft.com' -Current $script:Current } | Should -Not -Throw
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly
    }

    It 'throws when every write failed' {
        Mock New-GraphPOSTRequest { throw 'denied' }
        { Invoke-CIPPBaselinePlannerBlockTaskDelete -Remediate @{} -TenantFilter 'contoso.onmicrosoft.com' -Current $script:Current } | Should -Throw '*all 2 writes failed*'
    }
}
