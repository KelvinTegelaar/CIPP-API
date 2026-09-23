BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPBecReport { param($TenantFilter, $CaseId, $UserId, [switch]$IncludeResults) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListBECReports.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function New-Request {
        param([hashtable]$Query = @{})
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ListBECReports' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = 'x' }
            Query   = [pscustomobject]$Query
            Body    = $null
        }
    }
    # Rows as Get-CIPPBecReport hands them over: the table columns plus the CaseId/Tenant aliases, Containment
    # already parsed. A run that was never contained has no Containment column at all - New-CIPPBecRunRequest
    # does not write one and Invoke-CIPPBecContainment only writes it once there is an entry.
    $script:Contained = [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'BEC-20260820120000-aaa001'; CaseId = 'BEC-20260820120000-aaa001'; Tenant = 'contoso.com'; UserId = 'u1'; UserPrincipalName = 'victim@contoso.com'; DisplayName = 'Victim'; Status = 'Completed'; Level = 'High'; Score = 82; IncompleteCount = 0; ExtractedAt = '2026-08-20T12:20:00Z'; RequestedAt = '2026-08-20T12:00:00Z'; RequestedBy = 'tech@msp.com'; ErrorMessage = $null; EvidenceSha256 = 'abc'; LastContainmentAt = '2026-08-20T13:00:00Z'; Containment = @([pscustomobject]@{ At = '2026-08-20T12:30:00Z'; By = 'tech@msp.com'; Actions = @('RevokeSessions') }, [pscustomobject]@{ At = '2026-08-20T13:00:00Z'; By = 'tech@msp.com'; Actions = @('ResetPassword') }) }
    $script:Fresh = [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'BEC-20260821090000-bbb002'; CaseId = 'BEC-20260821090000-bbb002'; Tenant = 'contoso.com'; UserId = 'u2'; UserPrincipalName = 'other@contoso.com'; Status = 'Waiting'; RequestedAt = '2026-08-21T09:00:00Z'; RequestedBy = 'tech@msp.com' }
}

Describe 'Invoke-ListBECReports' {
    BeforeEach {
        Mock Get-CIPPBecReport { @($script:Contained, $script:Fresh) }
    }

    It 'returns the runs as a plain array projected to the list columns, never the table keys or evidence internals' {
        $Response = Invoke-ListBECReports -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        ($Response.Body -is [array]) | Should -BeTrue
        $Response.Body.Count | Should -Be 2
        $Response.Body[0].PSObject.Properties.Name | Should -Be @('CaseId', 'Tenant', 'UserId', 'UserPrincipalName', 'DisplayName', 'Status', 'Level', 'Score', 'IncompleteCount', 'ExtractedAt', 'RequestedAt', 'RequestedBy', 'ErrorMessage', 'ContainmentRuns')
        $Response.Body[0].CaseId | Should -Be 'BEC-20260820120000-aaa001'
        $Response.Body[0].Tenant | Should -Be 'contoso.com'
        $Response.Body[0].Score | Should -Be 82
        $Response.Body[0].RequestedBy | Should -Be 'tech@msp.com'
        $Response.Body[1].Status | Should -Be 'Waiting'
        $Response.Body[1].Level | Should -BeNullOrEmpty
    }

    It 'counts the containment runs of a run that was contained twice' {
        $Response = Invoke-ListBECReports -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
        $Response.Body[0].ContainmentRuns | Should -Be 2
    }

    It 'counts no containment runs for a run that was never contained' {
        $Response = Invoke-ListBECReports -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
        $Response.Body[1].ContainmentRuns | Should -Be 0 -Because 'a fresh run row has no Containment column and must not read as already contained'
    }

    It 'narrows to one user when userId is given, and only then' {
        $null = Invoke-ListBECReports -Request (New-Request @{ tenantFilter = 'contoso.com'; userId = 'u1' }) -TriggerMetadata $null
        Should -Invoke Get-CIPPBecReport -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $UserId -eq 'u1' -and [string]::IsNullOrEmpty($CaseId) -and -not $IncludeResults.IsPresent }
        $null = Invoke-ListBECReports -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
        Should -Invoke Get-CIPPBecReport -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.com' -and [string]::IsNullOrEmpty($UserId) }
    }

    It 'lists every tenant when tenantFilter is absent' {
        $null = Invoke-ListBECReports -Request (New-Request) -TriggerMetadata $null
        Should -Invoke Get-CIPPBecReport -Times 1 -ParameterFilter { $TenantFilter -eq 'AllTenants' -and [string]::IsNullOrEmpty($UserId) }
    }

    It 'keeps the array shape for zero runs and for a single run' {
        Mock Get-CIPPBecReport { @() }
        $Empty = Invoke-ListBECReports -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
        $Empty.StatusCode | Should -Be 200
        ($Empty.Body -is [array]) | Should -BeTrue
        $Empty.Body.Count | Should -Be 0
        Mock Get-CIPPBecReport { $script:Contained }
        $Single = Invoke-ListBECReports -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
        ($Single.Body -is [array]) | Should -BeTrue -Because 'the table page only renders Array.isArray data'
        $Single.Body.Count | Should -Be 1
        $Single.Body[0].CaseId | Should -Be 'BEC-20260820120000-aaa001'
    }

    It 'reports a storage failure as a formatted error' {
        Mock Get-CIPPBecReport { throw 'BecReports table unavailable' }
        $Response = Invoke-ListBECReports -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be 'Failed to list BEC runs: BecReports table unavailable'
    }
}
