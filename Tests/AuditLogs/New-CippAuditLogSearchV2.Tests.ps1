BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AuditLogs/New-CippAuditLogSearchV2.ps1')

    function New-GraphMultiTenantBulkRequest { param($TenantRequests) }

    function New-Search {
        param($Tenant, $RowKey)
        @{ TenantFilter = $Tenant; RowKey = $RowKey; StartTime = (Get-Date).AddHours(-1); EndTime = (Get-Date) }
    }
}

Describe 'New-CippAuditLogSearchV2' {
    BeforeEach {
        Mock Start-Sleep {}
        $script:Calls = [System.Collections.Generic.List[object]]::new()
    }

    It 'sends one batch per tenant in a single call and maps each result back to its window' {
        Mock New-GraphMultiTenantBulkRequest {
            $script:Calls.Add($TenantRequests)
            foreach ($Tenant in $TenantRequests) {
                [pscustomobject]@{
                    TenantFilter = $Tenant.TenantFilter
                    Error        = $null
                    Responses    = @($Tenant.Requests | ForEach-Object { [pscustomobject]@{ id = $_.id; status = 201; body = [pscustomobject]@{ id = "search-$($_.id)"; status = 'notStarted' } } })
                }
            }
        }

        $Results = New-CippAuditLogSearchV2 -Searches @((New-Search 'a.com' 'w1'), (New-Search 'b.com' 'w1'), (New-Search 'a.com' 'w2'))

        $script:Calls.Count | Should -Be 1
        @($script:Calls[0]).Count | Should -Be 2
        @($script:Calls[0][0].Requests).Count | Should -Be 2
        $Results.Count | Should -Be 3
        $Results[1].TenantFilter | Should -Be 'b.com'
        $Results[2].RowKey | Should -Be 'w2'
        $Results[2].Id | Should -Be 'search-2'
        @($Results.Outcome | Select-Object -Unique) | Should -Be @('Created')
    }

    It 'returns a 429 as throttled without re-sending it' {
        Mock New-GraphMultiTenantBulkRequest {
            [pscustomobject]@{ TenantFilter = 'a.com'; Error = $null; Responses = @([pscustomobject]@{ id = '0'; status = 429; body = [pscustomobject]@{ error = [pscustomobject]@{ code = 'TooManyRequests'; message = 'cap' } } }) }
        }

        $Result = @(New-CippAuditLogSearchV2 -Searches @(New-Search 'a.com' 'w1'))[0]

        $Result.Throttled | Should -BeTrue
        $Result.Outcome | Should -Be 'Transient'
        Should -Invoke New-GraphMultiTenantBulkRequest -Times 1 -Exactly
    }

    It 'treats a missing audit permission as access denied without retrying' {
        Mock New-GraphMultiTenantBulkRequest {
            $Message = '{"Message":"App:0531415b-c6ed-45e1-bac8-882ed3cde711 dont have any permissions"}'
            [pscustomobject]@{ TenantFilter = 'a.com'; Error = $null; Responses = @([pscustomobject]@{ id = '0'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ code = 'Forbidden'; message = $Message } } }) }
        }

        $Result = @(New-CippAuditLogSearchV2 -Searches @(New-Search 'a.com' 'w1'))[0]

        $Result.Outcome | Should -Be 'AccessDenied'
        $Result.Status | Should -Be 'MissingPermissions'
        Should -Invoke New-GraphMultiTenantBulkRequest -Times 1 -Exactly
    }

    It 'reads auditing disabled from the nested error message' {
        Mock New-GraphMultiTenantBulkRequest {
            $Message = '{"Status":"AuditingDisabledTenant"}'
            [pscustomobject]@{ TenantFilter = 'a.com'; Error = $null; Responses = @([pscustomobject]@{ id = '0'; status = 400; body = [pscustomobject]@{ error = [pscustomobject]@{ code = 'BadRequest'; message = $Message } } }) }
        }

        @(New-CippAuditLogSearchV2 -Searches @(New-Search 'a.com' 'w1'))[0].Outcome | Should -Be 'AuditingDisabled'
    }

    It 'classifies a missing service principal from the token error' {
        Mock New-GraphMultiTenantBulkRequest {
            [pscustomobject]@{ TenantFilter = 'a.com'; Error = 'Could not get token: AADSTS7000229: missing service principal'; Responses = @() }
        }

        $Result = @(New-CippAuditLogSearchV2 -Searches @(New-Search 'a.com' 'w1'))[0]

        $Result.Outcome | Should -Be 'AccessDenied'
        $Result.Status | Should -Be 'MissingServicePrincipal'
    }

    It 're-sends only the transient failures, up to MaxAttempts' {
        Mock New-GraphMultiTenantBulkRequest {
            $script:Calls.Add($TenantRequests)
            foreach ($Tenant in $TenantRequests) {
                [pscustomobject]@{
                    TenantFilter = $Tenant.TenantFilter
                    Error        = $null
                    Responses    = @($Tenant.Requests | ForEach-Object {
                            if ($Tenant.TenantFilter -eq 'bad.com') {
                                [pscustomobject]@{ id = $_.id; status = 500; body = [pscustomobject]@{ error = [pscustomobject]@{ code = 'UnknownError'; message = 'oops' } } }
                            } else {
                                [pscustomobject]@{ id = $_.id; status = 201; body = [pscustomobject]@{ id = 'search'; status = 'notStarted' } }
                            }
                        })
                }
            }
        }

        $Results = New-CippAuditLogSearchV2 -Searches @((New-Search 'good.com' 'w1'), (New-Search 'bad.com' 'w1'))

        $script:Calls.Count | Should -Be 3
        @($script:Calls[1].TenantFilter) | Should -Be @('bad.com')
        $Results[0].Outcome | Should -Be 'Created'
        $Results[1].Outcome | Should -Be 'Transient'
        $Results[1].Status | Should -Be 'UnknownError'
    }

    It 'treats a sub-request missing from the batch reply as transient' {
        Mock New-GraphMultiTenantBulkRequest { [pscustomobject]@{ TenantFilter = 'a.com'; Error = $null; Responses = @() } }

        @(New-CippAuditLogSearchV2 -Searches @(New-Search 'a.com' 'w1') -MaxAttempts 1)[0].Outcome | Should -Be 'Transient'
    }
}
