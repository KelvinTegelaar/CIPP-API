using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
try { 
    if ($request.query.Selected) {
        $BackupTables = $request.query.Selected -split ','
    }
    else {
        $BackupTables = @(
            "bpa"
            "Config"
            "Domains"
            "ExcludedLicenses"
            "templates"
            "standards"
            "SchedulerConfig"
        )
    }
    $CSVfile = foreach ($CSVTable in $BackupTables) {
        $Table = Get-CippTable -tablename $CSVTable
        Get-CIPPAzDataTableEntity @Table | Select-Object *, @{l = 'table'; e = { $CSVTable } }
    }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Created backup" -Sev "Debug"

    $body = [pscustomobject]@{
        "Results" = "Created backup"; 
        backup    = $CSVfile
    }
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME -message "Failed to create backup: $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Backup Creation failed: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
