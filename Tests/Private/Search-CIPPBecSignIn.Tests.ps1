BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp, $Version, $NoPaginateIds) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Search-CIPPBecSignIn.ps1')
    $script:Start = [datetime]::new(2026, 9, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    $script:End = [datetime]::new(2026, 10, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
}

Describe 'Search-CIPPBecSignIn' {
    It 'reads a 30-day period as five 7-day slices in one batch, edge to edge' {
        Mock New-GraphBulkRequest { foreach ($Request in $Requests) { [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @() } } } }
        $null = Search-CIPPBecSignIn -TenantFilter 'contoso.com' -Filter "userId eq 'u1'" -StartDate $script:Start -EndDate $script:End -Select 'ipAddress' -AsApp $false
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            $Urls = @($Requests.url)
            $Urls.Count -eq 5 -and $asapp -eq $false -and -not $NoPaginateIds -and
            $Urls[0] -eq "auditLogs/signIns?`$filter=userId eq 'u1' and createdDateTime ge 2026-09-01T00:00:00Z and createdDateTime lt 2026-09-08T00:00:00Z&`$top=999&`$select=ipAddress" -and
            $Urls[4] -match 'createdDateTime ge 2026-09-29T00:00:00Z and createdDateTime lt 2026-10-01T00:00:00Z' -and
            (@($Requests.id) -join ',') -eq 's0,s1,s2,s3,s4'
        }
    }

    It 'returns the rows newest first and flags a slice Graph stopped paging' {
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 's0'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'old' }) } }
                [pscustomobject]@{ id = 's4'; status = 200; PagingIncomplete = $true; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'new2' }, [pscustomobject]@{ id = 'new1' }) } }
                [pscustomobject]@{ id = 's2'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'mid' }) } }
            )
        }
        $Result = Search-CIPPBecSignIn -TenantFilter 'contoso.com' -Filter "userId eq 'u1'" -StartDate $script:Start -EndDate $script:End
        (@($Result.Rows.id) -join ',') | Should -Be 'new2,new1,mid,old'
        $Result.Incomplete | Should -BeTrue
    }

    It 'throws when a slice fails, as a single search would' {
        Mock New-GraphBulkRequest { @([pscustomobject]@{ id = 's0'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Tenant does not have a premium licence' } } }) }
        { Search-CIPPBecSignIn -TenantFilter 'contoso.com' -Filter "userId eq 'u1'" -StartDate $script:Start -EndDate $script:End } | Should -Throw -ExpectedMessage '*premium licence*'
    }

    It 'does not call Graph for an empty period' {
        Mock New-GraphBulkRequest { throw 'should not be called' }
        (Search-CIPPBecSignIn -TenantFilter 'contoso.com' -Filter "userId eq 'u1'" -StartDate $script:End -EndDate $script:End).Rows.Count | Should -Be 0
    }
}