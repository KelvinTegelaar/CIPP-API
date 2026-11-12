# Pester tests for Set-CIPPDBCachePIMGroupEligibilitySchedules
# Eligibility is read app-only per role-assignable group; eligible groups are resolved to their users.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp, $Version) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDBCacheSchedule.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCachePIMGroupEligibilitySchedules.ps1')

    function script:New-Eligibility {
        param($GroupId, $PrincipalId, $PrincipalType = 'user')
        [pscustomobject]@{
            id          = "${GroupId}_member_$PrincipalId"
            groupId     = $GroupId
            principalId = $PrincipalId
            accessId    = 'member'
            principal   = [pscustomobject]@{ '@odata.type' = "#microsoft.graph.$PrincipalType"; id = $PrincipalId; displayName = "Name $PrincipalId"; userPrincipalName = "$PrincipalId@contoso.com"; mail = 'dropped' }
        }
    }
}

Describe 'Set-CIPPDBCachePIMGroupEligibilitySchedules' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPDbItem { }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'pag-1'; displayName = 'Tier 0 Admins' }; [pscustomobject]@{ id = 'pag-2'; displayName = 'Helpdesk' } }
    }

    It 'reads eligibility app-only for each role-assignable group and resolves the users behind it' {
        Mock New-GraphBulkRequest {
            if ($Requests[0].url -like '*eligibilitySchedules*') {
                [pscustomobject]@{ id = 'pag-1'; status = 200; body = [pscustomobject]@{ value = @((script:New-Eligibility 'pag-1' 'sec-1' 'group'), (script:New-Eligibility 'pag-1' 'u1')) } }
                [pscustomobject]@{ id = 'pag-2'; status = 200; body = [pscustomobject]@{ value = @() } }
            } else {
                [pscustomobject]@{ id = 'sec-1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u2'; displayName = 'Nested User'; userPrincipalName = 'u2@contoso.com' }) } }
            }
        }

        Set-CIPPDBCachePIMGroupEligibilitySchedules -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/groups?$filter=isAssignableToRole eq true*' }
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            $asapp -eq $true -and @($Requests).Count -eq 2 -and $Requests[0].url -eq "/identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=groupId eq 'pag-1'&`$expand=principal"
        }
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests).Count -eq 1 -and $Requests[0].url -like '/groups/sec-1/transitiveMembers/microsoft.graph.user?*' }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'PIMGroupEligibilitySchedules' -and $AddCount -and -not $ClearOnEmpty -and @($Data).Count -eq 2 -and
            $Data[0].groupDisplayName -eq 'Tier 0 Admins' -and
            $Data[0].eligibleUsers -is [array] -and $Data[0].eligibleUsers.Count -eq 1 -and $Data[0].eligibleUsers[0].userPrincipalName -eq 'u2@contoso.com' -and
            $Data[1].eligibleUsers -is [array] -and $Data[1].eligibleUsers[0].id -eq 'u1' -and $null -eq $Data[1].eligibleUsers[0].mail
        }
    }

    It 'records an empty set when no group has an eligibility' {
        Mock New-GraphBulkRequest { [pscustomobject]@{ id = 'pag-1'; status = 200; body = [pscustomobject]@{ value = @() } } }

        Set-CIPPDBCachePIMGroupEligibilitySchedules -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'skips the eligibility read when the tenant has no role-assignable group' {
        Mock New-GraphGetRequest { }
        Mock New-GraphBulkRequest { }

        Set-CIPPDBCachePIMGroupEligibilitySchedules -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphBulkRequest -Times 0
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'writes nothing and rethrows when a group read fails' {
        Mock New-GraphBulkRequest {
            [pscustomobject]@{ id = 'pag-1'; status = 200; body = [pscustomobject]@{ value = @(script:New-Eligibility 'pag-1' 'u1') } }
            [pscustomobject]@{ id = 'pag-2'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Forbidden' } } }
        }

        { Set-CIPPDBCachePIMGroupEligibilitySchedules -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*pag-2*Forbidden*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }

    It 'is collected with the other PIM types and listed in the cache type registry' {
        (Get-CIPPDBCacheSchedule).PIM.Types | Should -Contain 'PIMGroupEligibilitySchedules'
        $Registry = Get-Content (Join-Path $RepoRoot 'Config/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json
        $Registry.type | Should -Contain 'PIMGroupEligibilitySchedules'
    }
}
