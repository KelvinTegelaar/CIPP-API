BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPBecReport { param($TenantFilter, $CaseId, $UserId, [switch]$IncludeResults) }
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties, $Results, [switch]$Replace) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First) }
    # Nothing in the evidence path may touch blob storage
    function New-CIPPAzStorageRequest { throw 'blob storage must not be touched' }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    # The reports are rendered server-side through the report builder + kit; stub them so the unit test
    # never loads OfficeIMO - the package's job here is collation, not the kit's PDF bytes.
    function Get-CippReportTenantName { param($TenantFilter) }
    function Build-CippBecReportTree { param($UserData, $BecData, $TenantName, $Variant) }
    function ConvertTo-CippReportPdf { param($Blocks, $Variables, $TenantName, $TenantFilter, $ReportName, $Branding, $BrandingPresetId, $GeneratedOn, $PageSize, [switch]$Landscape) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecEvidencePackage.ps1')

    $script:Run = [pscustomobject]@{
        CaseId = 'BEC-20260820120000-ev0001'; Status = 'Completed'; UserPrincipalName = 'victim@contoso.com'; UserId = 'u1'; ExtractedAt = '2026-08-20T12:05:00Z'; RequestedAt = '2026-08-20T12:00:00Z'; Score = 12; Level = 'High'
        Containment = @([pscustomobject]@{ At = '2026-08-20T13:00:00Z'; By = 'tech'; Actions = @('ResetPassword'); Results = @([pscustomobject]@{ Action = 'ResetPassword'; state = 'success'; resultText = 'The new password is [redacted]' }) })
        Results = [pscustomobject]@{
            CaseId = 'BEC-20260820120000-ev0001'
            NewRules = @([pscustomobject]@{ Name = 'Hide'; RiskReasons = @('Forwards or redirects messages', 'Deletes messages'); Nested = [pscustomobject]@{ a = 1 } })
            Delegations = @([pscustomobject]@{ PermissionType = 'FullAccess'; Trustee = 'x@example.org'; Flagged = $true })
            SentMessages = @()
            RiskState = [pscustomobject]@{ Listed = $true; Detections = @([pscustomobject]@{ RiskEventType = 'unfamiliarFeatures' }) }
            Score = [pscustomobject]@{ Value = 12; Level = 'High' }
        }
    }
    $script:FakePdf = [System.Text.Encoding]::ASCII.GetBytes('%PDF-1.4 fake')

    function Read-Zip {
        param([byte[]]$Bytes)
        $Stream = [System.IO.MemoryStream]::new($Bytes)
        $Archive = [System.IO.Compression.ZipArchive]::new($Stream, [System.IO.Compression.ZipArchiveMode]::Read)
        $Entries = @{}
        foreach ($Entry in $Archive.Entries) {
            $EntryStream = $Entry.Open()
            $Ms = [System.IO.MemoryStream]::new()
            $EntryStream.CopyTo($Ms)
            $Entries[$Entry.FullName] = $Ms.ToArray()
            $EntryStream.Dispose(); $Ms.Dispose()
        }
        $Archive.Dispose(); $Stream.Dispose()
        $Entries
    }
}

Describe 'New-CIPPBecEvidencePackage' {
    BeforeEach {
        Mock Get-CIPPBecReport { $script:Run }
        Mock Set-CIPPBecReport { }
        Mock Get-CIPPTable { @{ Context = @{ TableName = $TableName } } }
        Mock Get-CIPPAzDataTableEntity {
            @(
                [pscustomobject]@{ Timestamp = '2026-08-20T12:01:00Z'; Tenant = 'contoso.com'; API = 'BECRun'; Severity = 'Info'; Username = 'tech'; Message = 'BEC Check run'; LogData = ''; RowKey = 'l1' }
                [pscustomobject]@{ Timestamp = '2026-08-20T13:00:00Z'; Tenant = 'contoso.com'; API = 'BECRemediate'; Severity = 'Info'; Username = 'tech'; Message = 'Executed containment'; LogData = '[{"Action":"ResetPassword","copyField":"Hunter2!","resultText":"x"}]'; RowKey = 'l2' }
            )
        }
        Mock Write-LogMessage { }
        Mock Get-CippReportTenantName { 'Contoso' }
        Mock Build-CippBecReportTree { @{ Blocks = @(@{ type = 'blank' }); Variables = @{ coverlabel = 'Security Incident Report' } } }
        Mock ConvertTo-CippReportPdf { $script:FakePdf }
    }

    It 'builds a ZIP with the results, per-finding CSVs, score, containment, logbook and both server-rendered PDFs, and stores nothing' {
        $Package = New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-20260820120000-ev0001'
        $Package.Bytes | Should -BeGreaterThan 0
        $Entries = Read-Zip -Bytes $Package.ZipBytes
        $Entries.Keys | Should -Contain 'results.json'
        $Entries.Keys | Should -Contain 'findings/NewRules.csv'
        $Entries.Keys | Should -Contain 'findings/Delegations.csv'
        $Entries.Keys | Should -Contain 'findings/RiskDetections.csv'
        $Entries.Keys | Should -Not -Contain 'findings/SentMessages.csv' -Because 'empty sections are skipped'
        $Entries.Keys | Should -Contain 'score.json'
        $Entries.Keys | Should -Contain 'containment.json'
        $Entries.Keys | Should -Contain 'logbook.json'
        $Entries.Keys | Should -Contain 'report-full.pdf'
        $Entries.Keys | Should -Contain 'report-summary.pdf'
        $Entries.Count | Should -Be $Package.FileCount
        # rendered server-side: the full report and the summary variant, no browser round-trip
        Should -Invoke ConvertTo-CippReportPdf -Times 2
        Should -Invoke Build-CippBecReportTree -Times 1 -ParameterFilter { $Variant -eq 'summary' }
        Should -Invoke Set-CIPPBecReport -Times 0 -Because 'an export leaves no record on the run'
    }

    It 'flattens arrays and nested objects into CSV cells' {
        $Package = New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-20260820120000-ev0001'
        $Entries = Read-Zip -Bytes $Package.ZipBytes
        $Csv = [System.Text.Encoding]::UTF8.GetString($Entries['findings/NewRules.csv'])
        $Csv | Should -Match 'Forwards or redirects messages; Deletes messages'
        $Csv | Should -Match '\{""a"":1\}'
    }

    It 'still ships the rest of the package when the PDF render fails' {
        Mock ConvertTo-CippReportPdf { throw 'render boom' }
        $Package = New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-20260820120000-ev0001'
        $Entries = Read-Zip -Bytes $Package.ZipBytes
        $Entries.Keys | Should -Contain 'results.json'
        $Entries.Keys | Should -Not -Contain 'report-full.pdf'
        $Entries.Keys | Should -Not -Contain 'report-summary.pdf'
    }

    It 'scrubs any password copy field from the logbook copy and queries the case id across day partitions' {
        $Package = New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-20260820120000-ev0001'
        $Entries = Read-Zip -Bytes $Package.ZipBytes
        $Log = [System.Text.Encoding]::UTF8.GetString($Entries['logbook.json'])
        $Log | Should -Not -Match 'Hunter2'
        $Log | Should -Match '\[redacted\]'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -like "BecCaseId eq 'BEC-20260820120000-ev0001'*" -and $Filter -like "*PartitionKey ge '20260819'*" }
    }

    It 'refuses an incomplete run' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ Status = 'Waiting' } }
        { New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-x' } | Should -Throw '*only completed runs*'
    }
}
