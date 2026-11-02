# Pester tests for Invoke-ListUserReportedMessages.
#
# Pins the audit log paging contract: a capped two-week window is halved until it fits and the next
# page continues from the narrowed start (no reports skipped), paging stops at the 180-day retention,
# and a reported phish simulation logged twice collapses to one row.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListUserReportedMessages.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListUserReportedMessages.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Get-NormalizedError { param($Message) $Message }

    . $FunctionPath

    function New-AuditRecord {
        param([string]$Operation = 'UserSubmission', [string]$SubmissionId = [guid]::NewGuid().ToString())
        [pscustomobject]@{
            Operations = $Operation
            AuditData  = (@{
                    CreationTime  = '2026-10-09T07:34:03'
                    Operation     = $Operation
                    UserId        = 'user@contoso.com'
                    Subject       = 'Reported'
                    SubmissionId  = $SubmissionId
                    RescanResult  = @{ RescanVerdict = 'Phish' }
                } | ConvertTo-Json -Compress)
        }
    }

    function Invoke-List {
        param([hashtable]$Query)
        $Request = [pscustomobject]@{ Query = [pscustomobject]$Query }
        Invoke-ListUserReportedMessages -Request $Request -TriggerMetadata $null
    }
}

Describe 'Invoke-ListUserReportedMessages (audit log source)' {
    It 'halves a capped window and continues paging from the narrowed start' {
        # More than 5000 records in any window over 3.5 days, a handful below that
        Mock New-ExoRequest {
            $Span = ($cmdParams.EndDate - $cmdParams.StartDate).TotalDays
            $Count = if ($Span -gt 3.5) { 5000 } else { 3 }
            1..$Count | ForEach-Object { New-AuditRecord }
        }

        $Response = Invoke-List @{ tenantFilter = 'contoso.onmicrosoft.com' }

        # 14 -> 7 -> 3.5 days: three searches, the last one fits
        Should -Invoke New-ExoRequest -Times 3 -Exactly
        $Response.Body.Results.Count | Should -Be 3
        $Response.Body.Metadata.Complete | Should -BeTrue
        $Start = [datetime]::Parse($Response.Body.Metadata.WindowStart).ToUniversalTime()
        $End = [datetime]::Parse($Response.Body.Metadata.WindowEnd).ToUniversalTime()
        ($End - $Start).TotalDays | Should -Be 3.5
        $Response.Body.Metadata.nextLink | Should -Be $Response.Body.Metadata.WindowStart
    }

    It 'stops linking further pages at the 180-day retention' {
        Mock New-ExoRequest { New-AuditRecord }

        $Response = Invoke-List @{ tenantFilter = 'contoso.onmicrosoft.com'; nextLink = (Get-Date).ToUniversalTime().AddDays(-175).ToString('o') }

        $Response.Body.Metadata.PSObject.Properties.Name | Should -Not -Contain 'nextLink'
        $Start = [datetime]::Parse($Response.Body.Metadata.WindowStart).ToUniversalTime()
        ((Get-Date).ToUniversalTime() - $Start).TotalDays | Should -BeLessOrEqual 180.01
    }

    It 'collapses a reported phish simulation logged under both operations into one row' {
        Mock New-ExoRequest {
            New-AuditRecord -Operation 'UserSubmission' -SubmissionId 'sim-1'
            New-AuditRecord -Operation 'AttackSimUserSubmission' -SubmissionId 'sim-1'
            New-AuditRecord -Operation 'UserSubmission' -SubmissionId 'real-1'
        }

        $Response = Invoke-List @{ tenantFilter = 'contoso.onmicrosoft.com' }

        $Response.Body.Results.Count | Should -Be 2
        ($Response.Body.Results | Where-Object Id -EQ 'sim-1').Source | Should -Be 'AttackSimUserSubmission'
        $Response.Body.Results[0].ReportedDateTime | Should -Match 'Z$'
    }
}
