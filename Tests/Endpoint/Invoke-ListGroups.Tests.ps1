# Pester tests for the reporting-database branch of Invoke-ListGroups
# Validates the legacy bare-array shape and the manualPagination contract
# ({ Results, Metadata } pages chained via Metadata.nextLink).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    # Paged path returns a raw-JSON string Body; the legacy path returns an object.
    function ConvertFrom-ResponseBody {
        param($Response)
        if ($Response.Body -is [string]) { return ($Response.Body | ConvertFrom-Json) }
        return $Response.Body
    }

    # Stub every CIPP helper the exercised paths call so Pester's Mock has a command to replace.
    function Get-CIPPGroupsReport { param($TenantFilter, $PageSize, $ContinuationToken, [switch]$AsRawJson) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Get-GraphBulkResultByID { param($Results, $ID) }
    function Convert-AzureAdObjectIdToSid { param($ObjectID) }
    function Get-NormalizedError { param($Message) $Message }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Groups/Invoke-ListGroups.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript

    function New-GroupsRequest {
        param([hashtable]$Query = @{})
        $Merged = @{ tenantFilter = 'AllTenants' }
        foreach ($Key in $Query.Keys) { $Merged[$Key] = $Query[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListGroups' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]$Merged
        }
    }

    function New-GroupRow {
        param([string]$Id)
        [pscustomobject]@{
            id          = $Id
            displayName = "Group $Id"
            members     = @([pscustomobject]@{ id = 'u1'; userPrincipalName = 'u1@contoso.com' })
            membersCsv  = 'u1@contoso.com'
            Tenant      = 'contoso.onmicrosoft.com'
        }
    }

    # Mirror what Get-CIPPGroupsReport -AsRawJson returns: the group blobs pre-stitched
    # into a JSON array string, with a continuation token.
    function New-GroupsPageJson {
        param([object[]]$Rows, [string]$NextToken)
        $parts = foreach ($row in $Rows) { $row | ConvertTo-Json -Depth 10 -Compress }
        [PSCustomObject]@{
            CippPagedJson = '[' + ($parts -join ',') + ']'
            NextToken     = $NextToken
        }
    }
}

Describe 'Invoke-ListGroups report database branch' {
    BeforeEach {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'live Graph should not be called' }
        Mock -CommandName New-GraphBulkRequest -MockWith { throw 'live Graph should not be called' }
    }

    It 'returns the legacy bare array without manualPagination' {
        Mock -CommandName Get-CIPPGroupsReport -MockWith { @((New-GroupRow 'g1'), (New-GroupRow 'g2')) }

        $response = Invoke-ListGroups -Request (New-GroupsRequest) -TriggerMetadata $null

        $response.StatusCode | Should -Be 200
        $response.Body | Should -HaveCount 2
        $response.Body[0].members | Should -HaveCount 1
        Should -Invoke Get-CIPPGroupsReport -Times 1 -ParameterFilter {
            $TenantFilter -eq 'AllTenants' -and -not $PageSize
        }
    }

    It 'returns { Results, Metadata } pages with members intact when manualPagination is set' {
        Mock -CommandName Get-CIPPGroupsReport -MockWith {
            New-GroupsPageJson -Rows @((New-GroupRow 'g1')) -NextToken 'contoso.onmicrosoft.com|Groups-abc'
        }

        $response = Invoke-ListGroups -Request (New-GroupsRequest -Query @{
                manualPagination = 'true'; PageSize = '7'; nextLink = 'prev|token'
            }) -TriggerMetadata $null

        $response.StatusCode | Should -Be 200
        $response.ContentType | Should -Be 'application/json'
        $response.Body | Should -BeOfType [string]
        $body = ConvertFrom-ResponseBody $response
        $body.Results | Should -HaveCount 1
        $body.Results[0].members[0].userPrincipalName | Should -Be 'u1@contoso.com'
        $body.Metadata.nextLink | Should -Be 'contoso.onmicrosoft.com|Groups-abc'
        # PageSize 7 is below the 100 floor and must be clamped; the incoming token is
        # forwarded verbatim, and the read runs in raw-JSON mode.
        Should -Invoke Get-CIPPGroupsReport -Times 1 -ParameterFilter {
            $TenantFilter -eq 'AllTenants' -and $PageSize -eq 100 -and $ContinuationToken -eq 'prev|token' -and $AsRawJson
        }
    }

    It 'omits nextLink on the final page but keeps the paged shape and default size' {
        Mock -CommandName Get-CIPPGroupsReport -MockWith {
            New-GroupsPageJson -Rows @((New-GroupRow 'g1')) -NextToken $null
        }

        $response = Invoke-ListGroups -Request (New-GroupsRequest -Query @{
                UseReportDB = 'true'; manualPagination = 'true'
            }) -TriggerMetadata $null

        $body = ConvertFrom-ResponseBody $response
        $body.Results | Should -HaveCount 1
        $body.Metadata.nextLink | Should -BeNullOrEmpty
        $body.PSObject.Properties.Name | Should -Contain 'Metadata'
        Should -Invoke Get-CIPPGroupsReport -Times 1 -ParameterFilter { $PageSize -eq 750 }
    }

    It 'returns InternalServerError when the paged report read fails' {
        Mock -CommandName Get-CIPPGroupsReport -MockWith { throw 'No groups data found in reporting database for AllTenants. Sync the report data first.' }

        $response = Invoke-ListGroups -Request (New-GroupsRequest -Query @{ manualPagination = 'true' }) -TriggerMetadata $null

        $response.StatusCode | Should -Be 500
        "$($response.Body)" | Should -Match 'Sync the report data first'
    }
}
