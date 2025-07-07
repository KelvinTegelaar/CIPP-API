using namespace System.Net

function Invoke-ExecRestoreBackup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {

        if ($Request.Body.BackupName -like 'CippBackup_*') {
            $Table = Get-CippTable -tablename 'CIPPBackup'
            $Backup = Get-CippAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.BackupName)'"
            if ($Backup) {
                $BackupData = $Backup.Backup | ConvertFrom-Json -ErrorAction SilentlyContinue | Select-Object * -ExcludeProperty ETag, Timestamp
                $BackupData | ForEach-Object {
                    $Table = Get-CippTable -tablename $_.table
                    $ht2 = @{ }
                    $_.PSObject.Properties | ForEach-Object { $ht2[$_.Name] = [string]$_.Value }
                    $Table.Entity = $ht2
                    Add-CIPPAzDataTableEntity @Table -Force
                }
                Write-LogMessage -headers $Headers -API $APIName -message 'Created backup' -Sev 'Debug'
                $Body = [pscustomobject]@{
                    'Results' = 'Successfully restored backup.'
                }
            } else {
                $Body = [pscustomobject]@{
                    'Results' = 'Backup not found.'
                }
            }
        } else {
            foreach ($line in ($Request.Body | Select-Object * -ExcludeProperty ETag, Timestamp)) {
                $Table = Get-CippTable -tablename $line.table
                $ht2 = @{}
                $line.PSObject.Properties | ForEach-Object { $ht2[$_.Name] = [string]$_.Value }
                $Table.Entity = $ht2
                Add-AzDataTableEntity @Table -Force
            }
            Write-LogMessage -headers $Headers -API $APIName -message 'Created backup' -Sev 'Debug'

            $Body = [pscustomobject]@{
                'Results' = 'Successfully restored backup.'
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to restore backup: $($_.Exception.Message)" -Sev 'Error'
        $Body = [pscustomobject]@{'Results' = "Backup restore failed: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    return @{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
