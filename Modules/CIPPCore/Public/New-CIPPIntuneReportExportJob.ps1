function New-CIPPIntuneReportExportJob {
    <#
    .SYNOPSIS
        Submits an Intune report export job and stores the job id in the IntuneReportJobs table.

    .DESCRIPTION
        Posts an export job to deviceManagement/reports/exportJobs for the given report and upserts
        the job id into the IntuneReportJobs table (PartitionKey = tenant, RowKey = report name) so
        a later run can poll and download the result. Used by the nightly report-export orchestrator
        and by the DB cache functions to self-submit when no job is pending.

    .PARAMETER TenantFilter
        The tenant to submit the export job for.

    .PARAMETER ReportName
        The Intune report to export.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AppInvRawData', 'AppInstallStatusAggregate')]
        [string]$ReportName
    )

    $Select = switch ($ReportName) {
        'AppInvRawData' {
            @(
                'ApplicationKey', 'ApplicationName', 'ApplicationPublisher', 'ApplicationVersion',
                'DeviceId', 'DeviceName', 'OSDescription', 'OSVersion', 'Platform',
                'UserId', 'UserName', 'EmailAddress'
            )
        }
        'AppInstallStatusAggregate' {
            @(
                'ApplicationId', 'DisplayName', 'Publisher', 'Platform', 'AppVersion', 'AppPlatform',
                'InstalledDeviceCount', 'FailedDeviceCount', 'FailedUserCount',
                'PendingInstallDeviceCount', 'NotInstalledDeviceCount', 'FailedDevicePercentage'
            )
        }
    }

    $Body = @{
        reportName       = $ReportName
        format           = 'json'
        localizationType = 'replaceLocalizableValues'
        select           = $Select
    } | ConvertTo-Json -Depth 5

    $Job = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs' -tenantid $TenantFilter -body $Body

    if (-not $Job.id) { throw "Intune returned no job id for $ReportName" }

    $JobsTable = Get-CIPPTable -tablename 'IntuneReportJobs'
    $Existing = Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$ReportName'"
    if ($Existing) {
        Remove-AzDataTableEntity @JobsTable -Entity $Existing -Force -ErrorAction SilentlyContinue
    }

    Add-CIPPAzDataTableEntity @JobsTable -Entity @{
        PartitionKey = $TenantFilter
        RowKey       = $ReportName
        JobId        = $Job.id
        ReportName   = $ReportName
        SubmittedAt  = ([DateTime]::UtcNow).ToString('o')
    } -Force

    return $Job
}
