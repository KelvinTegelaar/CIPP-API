function Invoke-ExecGetStorageReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Server-renders the SharePoint & OneDrive Storage report as application/pdf bytes: site and OneDrive
        usage, per-library version history estimates and version policies, recycle bins and inactive sites.
        Reads the CIPP reporting cache only (usage sync and cleanup scan); nothing is read live.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter is required' })
        }
        $BrandingPresetId = [string]($Request.Body.brandingPresetId ?? $Request.Query.brandingPresetId)
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId $BrandingPresetId

        # The usage readers throw when their cache has never synced; the report then shows that section as empty.
        $Sites = try { @(Get-CIPPSharePointSiteUsageReport -TenantFilter $TenantFilter -ErrorAction Stop) } catch { @() }
        $OneDrive = try { @(Get-CIPPOneDriveUsageReport -TenantFilter $TenantFilter -ErrorAction Stop) } catch { @() }
        $Scan = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'StorageCleanupScan' -TableName 'CippStorageCleanupScan')

        $Report = Build-CippStorageReportTree -Data @{
            TenantName = $TenantName
            sites      = $Sites
            oneDrive   = $OneDrive
            scan       = $Scan
        }

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Storage Report' -BrandingPresetId $BrandingPresetId
        $FileName = ("Storage_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Storage report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
