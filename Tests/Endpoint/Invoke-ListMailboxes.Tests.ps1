# Pester tests for Invoke-ListMailboxes
# Validates the reporting-database branch: the legacy bare-array shape, and the
# manualPagination contract ({ Results, Metadata } pages chained via Metadata.nextLink).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Get-CIPPMailboxesReport { param($TenantFilter, $PageSize, $ContinuationToken) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select) }
    function Get-CIPPAutoExpandingArchiveState { param($MailboxAutoExpandingArchiveEnabled, $OrgAutoExpandingArchiveEnabled) }
    function Get-NormalizedError { param($Message) $Message }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Email-Exchange/Administration/Invoke-ListMailboxes.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript

    function New-MailboxRequest {
        param([hashtable]$Query = @{})
        $Merged = @{ tenantFilter = 'contoso.onmicrosoft.com' }
        foreach ($Key in $Query.Keys) { $Merged[$Key] = $Query[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListMailboxes' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]$Merged
        }
    }
}

Describe 'Invoke-ListMailboxes report database branch' {
    BeforeEach {
        Mock -CommandName New-ExoRequest -MockWith { throw 'live EXO should not be called' }
    }

    It 'returns the legacy bare array without manualPagination' {
        Mock -CommandName Get-CIPPMailboxesReport -MockWith {
            @(
                [pscustomobject]@{ displayName = 'Box One'; UPN = 'one@contoso.com'; CacheTimestamp = '2026-08-18T10:00:00Z' }
                [pscustomobject]@{ displayName = 'Box Two'; UPN = 'two@contoso.com'; CacheTimestamp = '2026-08-18T10:00:00Z' }
            )
        }

        $response = Invoke-ListMailboxes -Request (New-MailboxRequest -Query @{ UseReportDB = 'true' }) -TriggerMetadata $null

        $response.StatusCode | Should -Be 200
        $response.Body | Should -HaveCount 2
        $response.Body[0].displayName | Should -Be 'Box One'
        Should -Invoke Get-CIPPMailboxesReport -Times 1 -ParameterFilter {
            $TenantFilter -eq 'contoso.onmicrosoft.com' -and -not $PageSize
        }
    }

    It 'returns { Results, Metadata } pages when manualPagination is set' {
        Mock -CommandName Get-CIPPMailboxesReport -MockWith {
            [PSCustomObject]@{
                Items     = @(
                    [pscustomobject]@{ displayName = 'Box One'; UPN = 'one@contoso.com'; Tenant = 'contoso.onmicrosoft.com' }
                )
                NextToken = 'contoso.onmicrosoft.com|Mailboxes-abc'
            }
        }

        $response = Invoke-ListMailboxes -Request (New-MailboxRequest -Query @{
                tenantFilter = 'AllTenants'; UseReportDB = 'true'; manualPagination = 'true'; PageSize = '9999'; nextLink = 'prev|token'
            }) -TriggerMetadata $null

        $response.StatusCode | Should -Be 200
        $response.Body.Results | Should -HaveCount 1
        $response.Body.Results[0].displayName | Should -Be 'Box One'
        $response.Body.Metadata.nextLink | Should -Be 'contoso.onmicrosoft.com|Mailboxes-abc'
        # PageSize 9999 is inside the 250-10000 clamp and passes through; the incoming
        # continuation token is forwarded verbatim.
        Should -Invoke Get-CIPPMailboxesReport -Times 1 -ParameterFilter {
            $TenantFilter -eq 'AllTenants' -and $PageSize -eq 9999 -and $ContinuationToken -eq 'prev|token'
        }
    }

    It 'omits nextLink on the final page but keeps the paged shape' {
        Mock -CommandName Get-CIPPMailboxesReport -MockWith {
            [PSCustomObject]@{
                Items     = @([pscustomobject]@{ displayName = 'Box One' })
                NextToken = $null
            }
        }

        $response = Invoke-ListMailboxes -Request (New-MailboxRequest -Query @{
                UseReportDB = 'true'; manualPagination = 'true'
            }) -TriggerMetadata $null

        $response.StatusCode | Should -Be 200
        $response.Body.Results | Should -HaveCount 1
        $response.Body.Metadata.nextLink | Should -BeNullOrEmpty
        $response.Body.PSObject.Properties.Name | Should -Contain 'Metadata'
        # No PageSize in the request: the default lands between the clamp bounds.
        Should -Invoke Get-CIPPMailboxesReport -Times 1 -ParameterFilter { $PageSize -eq 5000 }
    }

    It 'returns InternalServerError when the paged report read fails' {
        Mock -CommandName Get-CIPPMailboxesReport -MockWith { throw 'No mailbox data found in reporting database. Sync the report data first.' }

        $response = Invoke-ListMailboxes -Request (New-MailboxRequest -Query @{
                UseReportDB = 'true'; manualPagination = 'true'
            }) -TriggerMetadata $null

        $response.StatusCode | Should -Be 500
        "$($response.Body)" | Should -Match 'Sync the report data first'
    }
}
