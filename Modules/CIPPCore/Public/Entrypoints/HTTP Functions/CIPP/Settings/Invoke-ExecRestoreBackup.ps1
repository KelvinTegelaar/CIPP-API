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

        if ($Request.Body.BackupName -like 'CippBackup_*') {
            $Table = Get-CippTable -tablename 'CIPPBackup'
            $Backup = Get-CippAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.BackupName)'"
            if ($Backup) {
                $BackupData = $Backup.Backup | ConvertFrom-Json -ErrorAction SilentlyContinue | Select-Object * -ExcludeProperty ETag, Timestamp
                $BackupData | ForEach-Object {
                    $Table = Get-CippTable -tablename $_.table
                    $ht2 = @{ }
                    $_.psobject.properties | ForEach-Object { $ht2[$_.Name] = [string]$_.Value }
                    $Table.Entity = $ht2
                    Add-CIPPAzDataTableEntity @Table -Force
                }
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Created backup' -Sev 'Debug'
                $body = [pscustomobject]@{
                    'Results' = 'Successfully restored backup.'
                }
            } else {
                $body = [pscustomobject]@{
                    'Results' = 'Backup not found.'
                }
            }
        } else {
            foreach ($line in ($Request.body | Select-Object * -ExcludeProperty ETag, Timestamp)) {
                $Table = Get-CippTable -tablename $line.table
                $ht2 = @{}
                $line.psobject.properties | ForEach-Object { $ht2[$_.Name] = [string]$_.Value }
                $Table.Entity = $ht2
                Add-CIPPAzDataTableEntity @Table -Force
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Created backup' -Sev 'Debug'

            $body = [pscustomobject]@{
                'Results' = 'Successfully restored backup.'
            }
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to restore backup: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Backup restore failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
