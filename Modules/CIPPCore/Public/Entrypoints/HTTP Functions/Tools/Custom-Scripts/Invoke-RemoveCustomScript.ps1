function Invoke-RemoveCustomScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Tests.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Headers = $Request.Headers

    try {
        $ScriptGuid = $Request.Query.ScriptGuid ?? $Request.Body.ScriptGuid

        if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
            throw 'ScriptGuid is required'
        }

        $Table = Get-CippTable -tablename 'CustomPowershellScripts'

        # Actually delete all versions of the script
        $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '{0}'" -f $ScriptGuid
        $Scripts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $Scripts) {
            throw "Script with GUID '$ScriptGuid' not found"
        }

        # Get script name for logging
        $ScriptName = ($Scripts | Select-Object -First 1).ScriptName

        # Delete all versions
        foreach ($script in $Scripts) {
            Remove-AzDataTableEntity @Table -Entity $script
        }

        # Delete matching test result rows for this custom script across tenants
        $CustomTestId = "CustomScript-$ScriptGuid"
        $TestResultsTable = Get-CippTable -tablename 'CippTestResults'
        $TestResultsFilter = "RowKey eq '{0}'" -f $CustomTestId
        $RelatedTestResults = @(Get-CIPPAzDataTableEntity @TestResultsTable -Filter $TestResultsFilter)
        foreach ($ResultRow in $RelatedTestResults) {
            Remove-AzDataTableEntity @TestResultsTable -Entity $ResultRow
        }

        # Remove this custom test from any custom report templates that include it
        $ReportTemplatesTable = Get-CippTable -tablename 'CippReportTemplates'
        $ReportTemplates = @(Get-CIPPAzDataTableEntity @ReportTemplatesTable -Filter "PartitionKey eq 'Report'")
        $UpdatedReports = 0
        foreach ($ReportTemplate in $ReportTemplates) {
            if ([string]::IsNullOrWhiteSpace([string]$ReportTemplate.CustomTests)) {
                continue
            }

            $CurrentCustomTests = @()
            try {
                $CurrentCustomTests = @($ReportTemplate.CustomTests | ConvertFrom-Json)
            } catch {
                continue
            }

            $FilteredCustomTests = @($CurrentCustomTests | Where-Object {
                    if ($_ -is [pscustomobject] -and $_.PSObject.Properties['id']) {
                        [string]$_.id -ne $CustomTestId
                    } else {
                        [string]$_ -ne $CustomTestId
                    }
                })
            if ($FilteredCustomTests.Count -ne $CurrentCustomTests.Count) {
                $ReportTemplate.CustomTests = [string]($FilteredCustomTests | ConvertTo-Json -Compress)
                $ReportTemplate.UpdatedAt = [string](Get-Date).ToString('o')
                Add-CIPPAzDataTableEntity @ReportTemplatesTable -Entity $ReportTemplate -Force
                $UpdatedReports++
            }
        }

        Write-LogMessage -API $APIName -headers $Headers -message "Deleted custom script: $ScriptName (Versions: $($Scripts.Count), TestResultsRemoved: $($RelatedTestResults.Count), ReportsUpdated: $UpdatedReports)" -sev 'Info'

        $Body = @{
            Results = "Successfully removed custom script '$ScriptName'"
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -headers $Headers -message "Failed to remove custom script: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = $Body
        })
}
