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

    # Types natively supported by Azure Table Storage — preserve these as-is
    $AzureTableTypes = @(
        [string], [int], [long], [double], [bool], [datetime], [guid], [byte[]]
    )
    $RestrictedTables = @('AccessRoleGroups', 'AccessIPRanges', 'CustomRoles') # tables that require superadmin to restore

    # Resolve the calling user's roles, including Entra group-based roles
    $CallingUser = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json
    if (($CallingUser.userRoles | Measure-Object).Count -eq 2 -and $CallingUser.userRoles -contains 'authenticated' -and $CallingUser.userRoles -contains 'anonymous') {
        $CallingUser = Test-CIPPAccessUserRole -User $CallingUser
    }
    $IsSuperAdmin = $CallingUser.userRoles -contains 'superadmin'

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

                $SelectedTypes = $Request.Body.SelectedTypes
                if ($SelectedTypes -and $SelectedTypes.Count -gt 0) {
                    $BackupData = $BackupData | Where-Object {
                        $item = $_
                        if ($item.table -eq 'templates') {
                            $typeKey = "templates:$($item.PartitionKey)"
                        } else {
                            $typeKey = $item.table
                        }
                        $SelectedTypes -contains $typeKey
                    }
                }
                $RestoredCount = 0
                $BackupData | ForEach-Object {
                    if ($_.table -like 'cache*') {
                        return
                    }
                    if ($_.table -eq 'Config' -and $_.PartitionKey -eq 'OffloadFunctions') {
                        return
                    }
                    if ($RestrictedTables -contains $_.table -and -not $IsSuperAdmin) {
                        Write-Information "Skipping restricted table '$($_.table)' - user does not have superadmin rights"
                        return
                    }
                    $Table = Get-CippTable -tablename $_.table
                    $ht2 = @{}
                    $_.psobject.properties | Where-Object { $_.Name -ne 'table' } | ForEach-Object {
                        $val = $_.Value
                        $ht2[$_.Name] = if ($null -ne $val -and $AzureTableTypes -contains $val.GetType()) { $val } else { [string]$val }
                    }
                    $Table.Entity = $ht2
                    Add-AzDataTableEntity @Table -Force
                    $RestoredCount++
                }
                Write-LogMessage -headers $Request.Headers -API $APINAME -message "Restored backup $($Request.Body.BackupName) - $RestoredCount rows restored" -Sev 'Info'
                $body = [pscustomobject]@{
                    'Results' = "Successfully restored $RestoredCount rows from backup."
                }
            } else {
                $body = [pscustomobject]@{
                    'Results' = 'Backup not found.'
                }
            }
        } else {
            $RestoredCount = 0
            foreach ($line in ($Request.body | Select-Object * -ExcludeProperty ETag, Timestamp)) {
                if ($line.table -like 'cache*') {
                    continue
                }
                if ($line.table -eq 'Config' -and $line.PartitionKey -eq 'OffloadFunctions') {
                    continue
                }
                if ($RestrictedTables -contains $line.table -and -not $IsSuperAdmin) {
                    Write-Information "Skipping restricted table '$($line.table)' - user does not have superadmin rights"
                    continue
                }
                $Table = Get-CippTable -tablename $line.table
                $ht2 = @{}
                $line.psobject.properties | Where-Object { $_.Name -ne 'table' } | ForEach-Object {
                    $val = $_.Value
                    $ht2[$_.Name] = if ($null -ne $val -and $AzureTableTypes -contains $val.GetType()) { $val } else { [string]$val }
                }
                $Table.Entity = $ht2
                Add-AzDataTableEntity @Table -Force
                $RestoredCount++
            }
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Restored backup - $RestoredCount rows restored" -Sev 'Info'

            $body = [pscustomobject]@{
                'Results' = "Successfully restored $RestoredCount rows from backup."
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
