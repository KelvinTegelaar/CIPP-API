function Invoke-ExecSharePointAccessReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .SYNOPSIS
        Start or delete a SharePoint Advanced Management access report
    .DESCRIPTION
        Starts a SharePoint Advanced Management site permissions report (every SharePoint site or
        OneDrive with who can reach it) or user permissions report (every site the selected users can
        reach), or deletes a report. Microsoft builds reports in the background: the first site
        permissions report takes up to 5 days, later ones usually under 24 hours. Microsoft allows a
        report to be run again only every 30 days and keeps at most five user reports per tenant;
        deleting old reports frees a slot.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Create or Delete
    $Action = $Request.Body.Action
    # SitePermissions or UserPermissions, for Create
    $ReportType = $Request.Body.ReportType.value ?? $Request.Body.ReportType
    # sharePoint or oneDrive, for Create
    $Workload = $Request.Body.Workload.value ?? $Request.Body.Workload
    # User principal names to report on, for a UserPermissions report
    $Users = @(foreach ($User in @($Request.Body.Users)) { if ($User.value ?? $User) { [string]($User.value ?? $User) } })
    # The report to delete, for Delete
    $ReportId = $Request.Body.ReportId

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Select a single tenant: access reports run per tenant.' } })
    }
    switch ($Action) {
        'Create' {
            if ($ReportType -notin 'SitePermissions', 'UserPermissions') {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ReportType must be SitePermissions or UserPermissions.' } })
            }
            if ($Workload -notin 'sharePoint', 'oneDrive') {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Workload must be sharePoint or oneDrive.' } })
            }
            if ($ReportType -eq 'UserPermissions' -and $Users.Count -eq 0) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Select at least one user for a user permissions report.' } })
            }
        }
        'Delete' {
            $ReportGuid = [guid]::Empty
            if (-not [guid]::TryParse([string]$ReportId, [ref]$ReportGuid)) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ReportId must be a report id (GUID).' } })
            }
        }
        default {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Action must be Create or Delete.' } })
        }
    }

    $WorkloadLabel = if ($Workload -eq 'oneDrive') { 'OneDrive' } else { 'SharePoint' }
    try {
        if ($Action -eq 'Delete') {
            $null = Invoke-CIPPSPOAccessReportRequest -TenantFilter $TenantFilter -Path "/$ReportGuid" -Method DELETE
            $Result = 'Deleted the access report.'
        } else {
            $Stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')
            if ($ReportType -eq 'SitePermissions') {
                $ReportName = "CIPP $WorkloadLabel site permissions $Stamp"
                $Path = '/createSitePermissionsReport'
                $Payload = @{
                    format                    = 'FullDetails'
                    workLoad                  = $Workload
                    sitePermissionsParameters = @{ reportName = $ReportName; siteTemplates = @('All'); labelIds = @('All'); privacySetting = 'All'; userLimit = 0 }
                }
            } else {
                $ReportName = "CIPP $WorkloadLabel user permissions $Stamp"
                $Path = '/createPermissionsReport'
                $Payload = @{
                    format                = 'FullDetails'
                    workLoad              = $Workload
                    entity                = 'UserPermissions'
                    permissionsParameters = @{ reportName = $ReportName; siteTemplates = @(); labelIds = @(); privacySetting = $null; userLimit = 0; userEmailList = $Users }
                }
            }
            $Created = Invoke-CIPPSPOAccessReportRequest -TenantFilter $TenantFilter -Path $Path -Method POST -Body (ConvertTo-Json -InputObject $Payload -Depth 5 -Compress)
            $Result = "Started '$ReportName'$(if ($Created.status) { " (status: $($Created.status))" }). Microsoft builds the report in the background: the first site permissions report can take up to 5 days, later reports usually finish within 24 hours."
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Verb = if ($Action -eq 'Delete') { 'delete' } else { 'start' }
        $Result = "Failed to $Verb the access report: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
