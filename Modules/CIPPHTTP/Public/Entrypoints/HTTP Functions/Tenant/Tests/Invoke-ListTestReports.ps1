function Invoke-ListTestReports {
    <#
    .SYNOPSIS
        Lists all available test reports from JSON files and database

    .FUNCTIONALITY
        Entrypoint,AnyTenant

    .ROLE
        Tenant.Reports.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        # Get reports from JSON files in test folders
        $ReportsRootPath = Join-Path $env:CIPPRootPath 'Modules\CIPPTests\Public\Tests'
        $FileReports = [System.IO.Directory]::EnumerateFiles($ReportsRootPath, 'report.json', [System.IO.SearchOption]::AllDirectories) | ForEach-Object {
            try {
                $ReportContent = [System.IO.File]::ReadAllText($_) | ConvertFrom-Json
                $FolderName = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($_))
                [PSCustomObject]@{
                    id          = $FolderName.ToLower()
                    name        = $ReportContent.name ?? $FolderName
                    description = $ReportContent.description ?? ''
                    version     = $ReportContent.version ?? '1.0'
                    source      = 'file'
                    type        = $FolderName
                }
            } catch {
                $CurrentFolder = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($_))
                Write-LogMessage -API $APIName -message "Error reading report.json from $CurrentFolder $($_.Exception.Message)" -sev Warning
            }
        }

        # Get custom reports from CippReportTemplates table
        $ReportTable = Get-CippTable -tablename 'CippReportTemplates'
        $Filter = "PartitionKey eq 'Report'"
        $CustomReports = Get-CIPPAzDataTableEntity @ReportTable -Filter $Filter

        $DatabaseReports = foreach ($Report in $CustomReports) {
            $IdentityTests = @()
            $DevicesTests = @()
            $CustomTests = @()

            if ($Report.IdentityTests) {
                try {
                    $IdentityTests = @($Report.IdentityTests | ConvertFrom-Json)
                } catch {
                    $IdentityTests = @()
                }
            }

            if ($Report.DevicesTests) {
                try {
                    $DevicesTests = @($Report.DevicesTests | ConvertFrom-Json)
                } catch {
                    $DevicesTests = @()
                }
            }

            if ($Report.CustomTests) {
                try {
                    $CustomTests = @($Report.CustomTests | ConvertFrom-Json)
                } catch {
                    $CustomTests = @()
                }
            }

            [PSCustomObject]@{
                id          = $Report.RowKey
                name        = $Report.Name ?? 'Custom Report'
                description = $Report.Description ?? ''
                version     = $Report.Version ?? '1.0'
                source      = 'database'
                type        = 'custom'
                IdentityTests = $IdentityTests
                DevicesTests  = $DevicesTests
                CustomTests   = $CustomTests
            }
        }

        $Reports = @($FileReports) + @($DatabaseReports)

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Reports)

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "Error retrieving test reports: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
        })
}
