# Pester tests for Invoke-ExecAlertsList and Invoke-ExecSetSecurityAlert against Graph alerts_v2

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $IncidentsPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Incidents'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphGetRequest { param($uri, $tenantid) $script:lastGet = $uri; $script:alerts }
    function Get-GraphRequestList { param($TenantFilter, $Endpoint, $Parameters, $AsApp, $CacheStatus) }
    function New-GraphPOSTRequest { param($uri, $type, $tenantid, $body) $script:lastPatch = @{ Uri = $uri; Type = $type; Body = $body } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . (Join-Path $IncidentsPath 'Invoke-ExecAlertsList.ps1')
    . (Join-Path $IncidentsPath 'Invoke-ExecSetSecurityAlert.ps1')
}

Describe 'Invoke-ExecAlertsList' {
    BeforeAll {
        $script:alerts = @(
            [pscustomobject]@{
                id                    = 'a1'
                title                 = 'Suspicious sign-in'
                category              = 'InitialAccess'
                severity              = 'high'
                status                = 'new'
                firstActivityDateTime = '2026-09-30T10:00:00Z'
                evidence              = @(
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.security.userEvidence'; userAccount = [pscustomobject]@{ userPrincipalName = 'amy@contoso.com' } }
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.security.ipEvidence'; ipAddress = '203.0.113.5' }
                )
            }
            [pscustomobject]@{
                id                    = 'a2'
                title                 = 'Malware detected'
                category              = 'Execution'
                severity              = 'low'
                status                = 'inProgress'
                firstActivityDateTime = '2026-09-30T12:00:00Z'
                evidence              = @()
            }
        )
        $request = [pscustomobject]@{ Query = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com' } }
        $script:response = Invoke-ExecAlertsList -Request $request -TriggerMetadata $null
    }

    It 'reads alerts_v2' {
        $lastGet | Should -Match '/security/alerts_v2$'
        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
    }

    It 'maps v2 fields onto the table columns, newest first' {
        $rows = $response.Body.Results.MSResults
        $rows.Id | Should -Be @('a2', 'a1')
        $rows[1].EventDateTime | Should -Be '2026-09-30T10:00:00Z'
        @($rows[1].InvolvedUsers).userPrincipalName | Should -Be 'amy@contoso.com'
    }

    It 'counts v2 status values' {
        $response.Body.Results.NewAlertsCount | Should -Be 1
        $response.Body.Results.InProgressAlertsCount | Should -Be 1
        $response.Body.Results.SeverityHighAlertsCount | Should -Be 1
    }
}

Describe 'Invoke-ExecAlertsList for AllTenants' {
    It 'reads the alerts_v2 graph request cache and keeps each row''s tenant' {
        Mock Get-GraphRequestList {
            param($TenantFilter, $Endpoint, $Parameters, $AsApp, $CacheStatus)
            $CacheStatus.CachedTenants = 2; $CacheStatus.ExpectedTenants = 3
            [pscustomobject]@{ id = 'b1'; title = 'One'; status = 'new'; severity = 'high'; firstActivityDateTime = '2026-10-01T00:00:00Z'; Tenant = 'a.com'; CippStatus = 'Good' }
            [pscustomobject]@{ Tenant = 'c.com'; CippStatus = 'Could not connect to tenant.' }
        }
        $request = [pscustomobject]@{ Query = [pscustomobject]@{ tenantFilter = 'AllTenants' } }

        $response = Invoke-ExecAlertsList -Request $request -TriggerMetadata $null

        Should -Invoke Get-GraphRequestList -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'AllTenants' -and $Endpoint -eq 'security/alerts_v2' }
        @($response.Body.Results.MSResults).Tenant | Should -Be 'a.com'
        $response.Body.Results.NewAlertsCount | Should -Be 1
        ($response.Body.Metadata.CachedTenants, $response.Body.Metadata.ExpectedTenants) | Should -Be @(2, 3)
    }

    It 'passes the queue message on while the cache is filled' {
        Mock Get-GraphRequestList { [pscustomobject]@{ Queued = $true; QueueMessage = 'Loading'; QueueId = 'q1' } }
        $request = [pscustomobject]@{ Query = [pscustomobject]@{ tenantFilter = 'AllTenants' } }

        $response = Invoke-ExecAlertsList -Request $request -TriggerMetadata $null

        ($response.Body.Metadata.QueueMessage, $response.Body.Metadata.QueueId) | Should -Be @('Loading', 'q1')
        @($response.Body.Results.MSResults).Count | Should -Be 0
    }
}

Describe 'Invoke-ExecSetSecurityAlert' {
    It 'patches alerts_v2 with only the status' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSetSecurityAlert' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; GUID = 'a1'; Status = 'resolved' }
        }

        $response = Invoke-ExecSetSecurityAlert -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $lastPatch.Uri | Should -Match '/security/alerts_v2/a1$'
        $lastPatch.Type | Should -Be 'PATCH'
        $lastPatch.Body | Should -Be '{"status":"resolved"}'
    }
}
