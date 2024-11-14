using namespace System.Net

Function Invoke-ExecRestoreBackup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    try {
        foreach ($line in ($Request.body | ConvertFrom-Json | Select-Object * -ExcludeProperty ETag)) {
            Write-Host ($line)
            $Table = Get-CippTable -tablename $line.table
            $ht2 = @{}
            $line.psobject.properties | Where-Object { $_.Name -ne 'table' } | ForEach-Object { $ht2[$_.Name] = [string]$_.Value }
            $Table.Entity = $ht2
            Add-CIPPAzDataTableEntity @Table -Force

        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Created backup' -Sev 'Debug'

        $body = [pscustomobject]@{
            'Results' = 'Successfully restored backup.'
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create backup: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Backup Creation failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
