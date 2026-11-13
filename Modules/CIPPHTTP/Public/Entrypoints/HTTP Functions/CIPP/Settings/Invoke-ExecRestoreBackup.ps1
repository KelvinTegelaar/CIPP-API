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
    # Only tables a CIPP backup contains (New-CIPPBackup) may be restored; keep the two lists in step.
    $RestorableTables = @(
        'AppPermissions', 'AccessRoleGroups', 'allowedAppRoles', 'ApiClients', 'CippReplacemap', 'CustomPowershellScripts',
        'CustomData', 'CustomRoles', 'Config', 'CommunityRepos', 'Domains', 'GraphPresets', 'GDAPRoles', 'GDAPRoleTemplates',
        'ExcludedLicenses', 'templates', 'standards', 'SchedulerConfig', 'Extensions', 'WebhookRules', 'ScheduledTasks',
        'DeltaQueries', 'TenantProperties', 'TenantGroups', 'TenantGroupMembers', 'PartnerTenants', 'BaselineRollouts',
        'Baselines', 'BaselineRolloutState', 'Tenants', 'AccessIPRanges', 'allowedUsers'
    )
    $RestrictedTables = @('AccessRoleGroups', 'allowedAppRoles', 'AccessIPRanges', 'allowedUsers', 'ApiClients', 'CustomRoles') # tables that require superadmin to restore
    $SkippedTables = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Request permissions follow role impersonation and API client roles.
    $AllowedPermissions = Get-CippRequestAllowedPermissions
    $IsSuperAdmin = $AllowedPermissions -contains 'CIPP.SuperAdmin.ReadWrite'

    # A CIPP backup is instance-wide, so a caller limited to some tenants cannot restore it.
    if (@(Test-CIPPAccess -Request $Request -TenantList) -notcontains 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = [pscustomobject]@{ 'Results' = 'Restoring a CIPP backup requires access to all tenants.' }
            })
    }

    $StatusCode = [HttpStatusCode]::OK
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
                    if ($RestorableTables -notcontains $_.table -or ($RestrictedTables -contains $_.table -and -not $IsSuperAdmin)) {
                        $null = $SkippedTables.Add([string]$_.table)
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
                    'Results' = "Successfully restored $RestoredCount rows from backup.$(if ($SkippedTables.Count -gt 0) { " Skipped rows for tables you cannot restore: $(@($SkippedTables) -join ', ')." })"
                }
            } else {
                $StatusCode = [HttpStatusCode]::NotFound
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
                if ($RestorableTables -notcontains $line.table -or ($RestrictedTables -contains $line.table -and -not $IsSuperAdmin)) {
                    $null = $SkippedTables.Add([string]$line.table)
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
                'Results' = "Successfully restored $RestoredCount rows from backup.$(if ($SkippedTables.Count -gt 0) { " Skipped rows for tables you cannot restore: $(@($SkippedTables) -join ', ')." })"
            }
        }
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Failed to restore backup: $($_.Exception.Message)" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $body = [pscustomobject]@{'Results' = "Backup restore failed: $($_.Exception.Message)" }
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
