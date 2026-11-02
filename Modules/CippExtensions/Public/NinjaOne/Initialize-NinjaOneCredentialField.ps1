function Initialize-NinjaOneCredentialField {
    <#
    .SYNOPSIS
        Creates or adopts the NinjaOne device custom fields used for LAPS and BitLocker sync and maps them.
    .DESCRIPTION
        Only fields whose global switch is on and that are not mapped yet are handled; existing mappings are never changed.
        A field with the canonical fieldName is adopted, otherwise it is created. Adds every mapped field to MappedFields.
        Without Token and MappedFields, as when called from the settings save, the current mapping is read and a token requested.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        $Token,
        $MappedFields,
        $WebSession
    )

    if (-not $MappedFields) {
        $MappedFields = [pscustomobject]@{}
        foreach ($Row in @(Get-ExtensionMapping -Extension 'NinjaOneField' | Where-Object { $_.IntegrationId })) {
            $MappedFields | Add-Member -NotePropertyName $Row.RowKey -NotePropertyValue $Row.IntegrationId -Force
        }
    }

    $Definitions = @(
        @{ Name = 'LAPSAccount'; Switch = 'IncludeLAPS'; FieldName = 'cippLapsAccount'; Label = 'Windows LAPS Account'; Type = 'TEXT' }
        @{ Name = 'LAPSPassword'; Switch = 'IncludeLAPS'; FieldName = 'cippLapsPassword'; Label = 'Windows LAPS Password'; Type = 'TEXT_ENCRYPTED' }
        @{ Name = 'LAPSBackupDate'; Switch = 'IncludeLAPS'; FieldName = 'cippLapsBackupDate'; Label = 'Windows LAPS Backup Date'; Type = 'TEXT' }
        @{ Name = 'BitLockerKeyIds'; Switch = 'IncludeBitLocker'; FieldName = 'cippBitLockerKeyIds'; Label = 'BitLocker Key IDs'; Type = 'TEXT_MULTILINE' }
        @{ Name = 'BitLockerRecoveryKeys'; Switch = 'IncludeBitLocker'; FieldName = 'cippBitLockerRecoveryKeys'; Label = 'BitLocker Recovery Keys'; Type = 'TEXT_ENCRYPTED' }
    )
    $Needed = @($Definitions | Where-Object { [bool]$Configuration.($_.Switch) -and -not $MappedFields.($_.Name) })
    if ($Needed.Count -eq 0) { return }

    if (-not $Token) { $Token = Get-NinjaOneToken -configuration $Configuration -WebSession $WebSession }
    $Request = @{ Headers = @{ Authorization = "Bearer $($Token.access_token)" }; ContentType = 'application/json; charset=utf-8' }
    if ($WebSession) { $Request.WebSession = $WebSession }
    $ListUri = "https://$($Configuration.Instance)/api/v2/device-custom-fields?scopes=node"
    $GetFieldNames = { , [System.Collections.Generic.HashSet[string]]@(((Invoke-WebRequest @Request -Uri $ListUri -Method GET).Content | ConvertFrom-Json -Depth 100).name | Where-Object { $_ }) }

    try {
        $Existing = & $GetFieldNames
        $ToCreate = @($Needed | Where-Object { -not $Existing.Contains($_.FieldName) })
        if ($ToCreate.Count -gt 0) {
            $Body = ConvertTo-Json -Depth 10 -InputObject @{ customFields = @(foreach ($Field in $ToCreate) {
                    [ordered]@{
                        label                = $Field.Label
                        fieldName            = $Field.FieldName
                        description          = 'Managed by CIPP'
                        type                 = $Field.Type
                        scope                = 'NODE_ROLE'
                        definitionScope      = @('NODE')
                        technicianPermission = 'READ_ONLY'
                        scriptPermission     = 'NONE'
                        apiPermission        = 'WRITE_ONLY'
                        addToDefaultTab      = $true
                    }
                }) }
            try {
                $null = Invoke-WebRequest @Request -Uri "https://$($Configuration.Instance)/api/v2/custom-fields/bulk" -Method POST -Body $Body
                foreach ($Field in $ToCreate) { [void]$Existing.Add($Field.FieldName) }
            } catch {
                $CreateError = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
                if ($CreateError -match 'duplicate_attribute_names_detected') {
                    # Write-only fields never appear in the listing, so a duplicate rejection is the only proof they exist.
                    foreach ($Field in $ToCreate) { [void]$Existing.Add($Field.FieldName) }
                } else {
                    # Concurrent tenant syncs can race to create the same field; adopt whatever now exists.
                    $Existing = & $GetFieldNames
                }
            }
        }
    } catch {
        Write-LogMessage -API 'NinjaOneSync' -message "Unable to list NinjaOne device custom fields for credential sync: $($_.Exception.Message)" -Sev 'Warning'
        return
    }

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Missing = [System.Collections.Generic.List[string]]::new()
    foreach ($Field in $Needed) {
        if (-not $Existing.Contains($Field.FieldName)) { $Missing.Add($Field.FieldName); continue }
        $Rows.Add(@{ PartitionKey = 'NinjaOneFieldMapping'; RowKey = $Field.Name; IntegrationId = $Field.FieldName; IntegrationName = $Field.Label })
        $MappedFields | Add-Member -NotePropertyName $Field.Name -NotePropertyValue $Field.FieldName -Force
    }
    if ($Rows.Count -gt 0) {
        $CIPPMapping = Get-CIPPTable -TableName CippMapping
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity @($Rows) -Force
    }
    if ($Missing.Count -gt 0) {
        Write-LogMessage -API 'NinjaOneSync' -message "Unable to create NinjaOne credential custom fields $($Missing -join ', '), credential sync skipped this run: $CreateError" -Sev 'Warning'
    }
}
