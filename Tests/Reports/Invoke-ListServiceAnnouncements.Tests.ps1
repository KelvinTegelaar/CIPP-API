BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$ByTenant) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    $Reports = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Reports'
    . (Join-Path $Reports 'Invoke-ListServiceHealthOverviews.ps1')
    . (Join-Path $Reports 'Invoke-ListServiceHealthIssues.ps1')
    . (Join-Path $Reports 'Invoke-ListMessageCenterMessages.ps1')

    $script:T1 = [datetimeoffset]'2026-09-29T01:00:00Z'
    $script:T2 = [datetimeoffset]'2026-09-29T02:00:00Z'

    function New-Request {
        param($TenantFilter, [switch]$UseReportDB)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'Test' }
            Headers = @{}
            Query   = [pscustomobject]@{ tenantFilter = $TenantFilter; UseReportDB = [bool]$UseReportDB }
        }
    }
    function New-Row {
        param($Tenant, $Data, $Timestamp = $script:T1)
        [pscustomobject]@{ PartitionKey = $Tenant; Timestamp = $Timestamp; Data = $Data }
    }
}

Describe 'Service announcement list endpoints' {
    It 'returns cached overviews for one tenant with CacheTimestamp and no Tenant' {
        Mock Get-CIPPDbItem {
            [ordered]@{
                'a.com' = [System.Collections.Generic.List[object]]@(
                    (New-Row 'a.com' '{"id":"Exchange","status":"serviceOperational"}')
                    (New-Row 'a.com' '{"id":"SharePoint","status":"serviceDegradation"}' $script:T2)
                )
            }
        }

        $Response = Invoke-ListServiceHealthOverviews -Request (New-Request 'a.com' -UseReportDB)

        $Response.StatusCode | Should -Be 200
        $Response.Body | Should -HaveCount 2
        $Response.Body[1].status | Should -Be 'serviceDegradation'
        $Response.Body[1].CacheTimestamp | Should -Be $script:T2
        $Response.Body[0].PSObject.Properties.Name | Should -Not -Contain 'Tenant'
        Should -Invoke Get-CIPPDbItem -Times 1 -ParameterFilter { $TenantFilter -eq 'a.com' -and $Type -eq 'ServiceHealthOverviews' -and $ByTenant }
    }

    It 'stamps Tenant on every AllTenants overview row' {
        Mock Get-CIPPDbItem {
            [ordered]@{
                'a.com' = [System.Collections.Generic.List[object]]@((New-Row 'a.com' '{"id":"Exchange","status":"serviceOperational"}'))
                'b.com' = [System.Collections.Generic.List[object]]@((New-Row 'b.com' '{"id":"Exchange","status":"serviceOperational"}'))
            }
        }

        $Response = Invoke-ListServiceHealthOverviews -Request (New-Request 'AllTenants')

        $Response.Body.Tenant | Should -Be @('a.com', 'b.com')
        Should -Invoke Get-CIPPDbItem -Times 1 -ParameterFilter { $TenantFilter -eq 'allTenants' }
    }

    It 'collapses AllTenants issues by id, keeping the newest copy and the tenants it reached' {
        Mock Get-CIPPDbItem {
            [ordered]@{
                'a.com' = [System.Collections.Generic.List[object]]@(
                    (New-Row 'a.com' '{"id":"EX1","title":"old","lastModifiedDateTime":"2026-09-28T00:00:00Z","details":[{"name":"AffectedChildWorkloads","value":"a-only"}]}')
                    (New-Row 'a.com' '{"id":"TM1","title":"teams","lastModifiedDateTime":"2026-09-28T00:00:00Z"}')
                )
                'b.com' = [System.Collections.Generic.List[object]]@(
                    (New-Row 'b.com' '{"id":"EX1","title":"new","lastModifiedDateTime":"2026-09-29T00:00:00Z"}' $script:T2)
                )
            }
        }

        $Response = Invoke-ListServiceHealthIssues -Request (New-Request 'AllTenants')

        $Response.Body | Should -HaveCount 2
        $Exchange = $Response.Body | Where-Object id -EQ 'EX1'
        $Exchange.title | Should -Be 'new'
        $Exchange.Tenants | Should -Be @('a.com', 'b.com')
        $Exchange.TenantCount | Should -Be 2
        $Exchange.Tenant | Should -Be '2 tenants'
        $Exchange.CacheTimestamp | Should -Be $script:T2
        $Exchange.TenantDetails.Tenant | Should -Be @('a.com', 'b.com')
        $Exchange.TenantDetails[0].details.value | Should -Be 'a-only'
        ($Response.Body | Where-Object id -EQ 'TM1').Tenant | Should -Be 'a.com'
    }

    It 'returns 500 with a sync hint when a tenant has no cached messages' {
        Mock Get-CIPPDbItem { [ordered]@{} }

        $Response = Invoke-ListMessageCenterMessages -Request (New-Request 'a.com' -UseReportDB)

        $Response.StatusCode | Should -Be 500
        $Response.Body | Should -Be 'No message center messages data found for a.com. Run a cache sync first.'
    }

    It 'calls Graph live for a single tenant without UseReportDB' {
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'MC1' }) }
        Mock Get-CIPPDbItem { [ordered]@{} }

        $Response = Invoke-ListMessageCenterMessages -Request (New-Request 'a.com')

        $Response.Body.id | Should -Be 'MC1'
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like '*/serviceAnnouncement/messages' -and $tenantid -eq 'a.com' }
        Should -Invoke Get-CIPPDbItem -Times 0
    }
}
