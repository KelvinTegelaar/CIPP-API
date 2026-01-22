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
    try {

        if ($Request.Body.BackupName -like 'CippBackup_*') {
            # Use Get-CIPPBackup which already handles fetching from blob storage
            $Backup = Get-CIPPBackup -Type 'CIPP' -Name $Request.Body.BackupName
            if ($Backup) {
                $raw = $Backup.Backup
                $BackupData = $null

                # Get-CIPPBackup already fetches blob content, so raw should be JSON string
                try {
                    if ($raw -is [string]) {
                        $BackupData = $raw | ConvertFrom-Json -ErrorAction Stop
                    } else {
                        $BackupData = $raw | Select-Object * -ExcludeProperty ETag, Timestamp
                    }
                } catch {
                    throw "Failed to parse backup JSON: $($_.Exception.Message)"
                }

                $BackupData | ForEach-Object {
                    $Table = Get-CippTable -tablename $_.table
                    $ht2 = @{}
                    $_.psobject.properties | ForEach-Object { $ht2[$_.Name] = [string]$_.Value }
                    $Table.Entity = $ht2
                    Add-CIPPAzDataTableEntity @Table -Force
                }
                Write-LogMessage -headers $Request.Headers -API $APINAME -message "Restored backup $($Request.Body.BackupName)" -Sev 'Info'
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
                Add-AzDataTableEntity @Table -Force
            }
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Restored backup $($Request.Body.BackupName)" -Sev 'Info'

            $body = [pscustomobject]@{
                'Results' = 'Successfully restored backup.'
            }
        }
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Failed to restore backup: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Backup restore failed: $($_.Exception.Message)" }
    }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
