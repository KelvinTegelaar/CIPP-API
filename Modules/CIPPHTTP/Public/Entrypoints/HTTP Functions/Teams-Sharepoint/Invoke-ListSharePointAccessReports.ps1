function Invoke-ListSharePointAccessReports {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .SYNOPSIS
        SharePoint Advanced Management access reports
    .DESCRIPTION
        Lists the SharePoint Advanced Management site permissions and user permissions reports
        generated in a tenant, whoever started them (CIPP or the SharePoint admin center), with their
        status. Microsoft builds each report in the background.

        With ReportId, returns the rows of that completed report instead: one row per SharePoint
        site or OneDrive with the number of users who can reach it, guest, Everyone and Everyone
        except external users permissions, items with unique permissions and sharing link counts.
        User permissions reports return one row per user and site they can reach. Counts only, no
        file or folder names.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # A completed report to return the rows of, instead of listing the reports
    $ReportId = $Request.Query.ReportId

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Select a single tenant: access reports are read per tenant.' } })
    }
    $ReportGuid = [guid]::Empty
    if ($ReportId -and -not [guid]::TryParse($ReportId, [ref]$ReportGuid)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ReportId must be a report id (GUID).' } })
    }

    try {
        if ($ReportId) {
            $Bytes = Invoke-CIPPSPOAccessReportRequest -TenantFilter $TenantFilter -Path "/$ReportGuid/content" -Content
            $IsZip = $Bytes.Length -ge 2 -and $Bytes[0] -eq 0x50 -and $Bytes[1] -eq 0x4B
            $CsvFiles = @(if ($IsZip) {
                    $Archive = [System.IO.Compression.ZipArchive]::new([System.IO.MemoryStream]::new($Bytes), [System.IO.Compression.ZipArchiveMode]::Read)
                    try {
                        foreach ($Entry in $Archive.Entries) {
                            if ($Entry.Name -notlike '*.csv') { continue }
                            $Reader = [System.IO.StreamReader]::new($Entry.Open(), [System.Text.Encoding]::UTF8, $true)
                            try { @{ Source = $Entry.Name.Substring(0, $Entry.Name.Length - 4); Text = $Reader.ReadToEnd() } } finally { $Reader.Dispose() }
                        }
                    } finally { $Archive.Dispose() }
                } else {
                    $Reader = [System.IO.StreamReader]::new([System.IO.MemoryStream]::new($Bytes), [System.Text.Encoding]::UTF8, $true)
                    try { @{ Source = $null; Text = $Reader.ReadToEnd() } } finally { $Reader.Dispose() }
                })
            $Bytes = $null

            # The CSV headers are display text ('Number of users having access'); camelCase them into field names.
            # User permissions reports hold one CSV per user; the file name is kept on each row as reportFile.
            $Results = foreach ($File in $CsvFiles) {
                $Csv = $File.Text
                $HeaderEnd = $Csv.IndexOf("`n")
                if ($HeaderEnd -lt 0) { continue }
                $Column = 0
                $Names = foreach ($Header in ($Csv.Substring(0, $HeaderEnd).Trim([char]0xFEFF, "`r", ' ') -split ',')) {
                    $Column++
                    $Words = @($Header.Trim('"', ' ') -split '[^A-Za-z0-9]+').Where({ $_ })
                    if ($Words.Count -eq 0) { "column$Column"; continue }
                    $Name = foreach ($Index in 0..($Words.Count - 1)) {
                        $Word = $Words[$Index]
                        if ($Word -ceq $Word.ToUpperInvariant()) { $Word = $Word.Substring(0, 1) + $Word.Substring(1).ToLowerInvariant() }
                        if ($Index -eq 0) { $Word.Substring(0, 1).ToLowerInvariant() + $Word.Substring(1) } else { $Word.Substring(0, 1).ToUpperInvariant() + $Word.Substring(1) }
                    }
                    -join $Name
                }
                if ($null -eq $File.Source) {
                    $Csv.Substring($HeaderEnd + 1) | ConvertFrom-Csv -Header $Names
                } else {
                    foreach ($Row in ($Csv.Substring($HeaderEnd + 1) | ConvertFrom-Csv -Header $Names)) {
                        $Row.PSObject.Properties.Add([psnoteproperty]::new('reportFile', $File.Source))
                        $Row
                    }
                }
            }
        } else {
            $Results = foreach ($Entity in 'SitePermissions', 'UserPermissions') {
                $Reports = Invoke-CIPPSPOAccessReportRequest -TenantFilter $TenantFilter -Path "/?filter=Entity eq '$Entity'"
                foreach ($Report in @($Reports.value)) {
                    $Parameters = if ($Entity -eq 'SitePermissions') { $Report.sitePermissionsParameters } else { $Report.permissionsParameters }
                    [PSCustomObject]@{
                        id                = $Report.id
                        name              = $Parameters.reportName
                        reportType        = if ($Entity -eq 'SitePermissions') { 'Site permissions' } else { 'User permissions' }
                        workload          = if ($Report.workLoad -eq 'oneDrive') { 'OneDrive' } else { 'SharePoint' }
                        status            = $Report.status
                        users             = @($Parameters.userEmailList) -join ', '
                        sitesInReport     = $Parameters.countOfSitesInReport
                        requestedDateTime = $Report.triggerDateTime
                        createdDateTime   = $Report.createdDateTime
                    }
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Body = @(if ($null -ne $Results) { $Results })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = "Failed to read SharePoint access reports: $($ErrorMessage.NormalizedError)" }
        if ($StatusCode -eq [HttpStatusCode]::InternalServerError) {
            Write-LogMessage -Headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message $Body.Results -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
