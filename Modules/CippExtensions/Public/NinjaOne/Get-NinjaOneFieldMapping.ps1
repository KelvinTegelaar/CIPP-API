function Get-NinjaOneFieldMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $Unset = [PSCustomObject]@{
        name  = '--- Do not synchronize ---'
        value = $null
        type  = 'unset'
    }

    try {
        #Get available mappings
        $Mappings = [pscustomobject]@{}

        [System.Collections.Generic.List[object]]$CIPPFieldHeaders = @(
            [PSCustomObject]@{
                Title       = 'NinjaOne Organization Global Custom Field Mapping'
                FieldType   = 'Organization'
                Description = 'Use the table below to map your Organization Field to the correct NinjaOne Field'
            }
            [PSCustomObject]@{
                Title       = 'NinjaOne Device Custom Field Mapping'
                FieldType   = 'Device'
                Description = 'Use the table below to map your Device Field to the correct NinjaOne Field. Credential fields (LAPS, BitLocker) are created automatically when their sync switches are on; to map your own, use Secure fields with API permission Write Only.'
            }
        )

        [System.Collections.Generic.List[object]]$CIPPFields = @(
            [PSCustomObject]@{
                FieldName  = 'TenantLinks'
                FieldLabel = 'Microsoft 365 Tenant Links - Field Used to Display Links to Microsoft 365 Portals and CIPP'
                FieldType  = 'Organization'
                Type       = 'WYSIWYG'
            },
            [PSCustomObject]@{
                FieldName  = 'TenantSummary'
                FieldLabel = 'Microsoft 365 Tenant Summary - Field Used to Display Tenant Summary Information'
                FieldType  = 'Organization'
                Type       = 'WYSIWYG'
            },
            [PSCustomObject]@{
                FieldName  = 'UsersSummary'
                FieldLabel = 'Microsoft 365 Users Summary - Field Used to Display User Summary Information'
                FieldType  = 'Organization'
                Type       = 'WYSIWYG'
            },
            [PSCustomObject]@{
                FieldName  = 'DeviceLinks'
                FieldLabel = 'Microsoft 365 Device Links - Field Used to Display Links to Microsoft 365 Portals and CIPP'
                FieldType  = 'Device'
                Type       = 'WYSIWYG'
            },
            [PSCustomObject]@{
                FieldName  = 'DeviceSummary'
                FieldLabel = 'Microsoft 365 Device Summary - Field Used to Display Device Summary Information'
                FieldType  = 'Device'
                Type       = 'WYSIWYG'
            },
            [PSCustomObject]@{
                FieldName  = 'DeviceCompliance'
                FieldLabel = 'Intune Device Compliance Status - Field Used to Monitor Device Compliance'
                FieldType  = 'Device'
                Type       = 'TEXT'
            },
            [PSCustomObject]@{
                FieldName  = 'DeviceNonCompliantSettings'
                FieldLabel = 'Intune Non-Compliant Settings - Field Used to List the Compliance Policy Settings a Device Fails'
                FieldType  = 'Device'
                Type       = @('TEXT_MULTILINE', 'TEXT')
            },
            [PSCustomObject]@{
                FieldName  = 'LAPSAccount'
                FieldLabel = 'Windows LAPS Account'
                FieldType  = 'Device'
                Type       = 'TEXT'
            },
            [PSCustomObject]@{
                FieldName  = 'LAPSPassword'
                FieldLabel = 'Windows LAPS Password'
                FieldType  = 'Device'
                Type       = 'TEXT_ENCRYPTED'
            },
            [PSCustomObject]@{
                FieldName  = 'LAPSBackupDate'
                FieldLabel = 'Windows LAPS Backup Date'
                FieldType  = 'Device'
                Type       = 'TEXT'
            },
            [PSCustomObject]@{
                FieldName  = 'BitLockerKeyIds'
                FieldLabel = 'BitLocker Key IDs'
                FieldType  = 'Device'
                Type       = @('TEXT_MULTILINE', 'TEXT')
            },
            [PSCustomObject]@{
                FieldName  = 'BitLockerRecoveryKeys'
                FieldLabel = 'BitLocker Recovery Keys'
                FieldType  = 'Device'
                Type       = 'TEXT_ENCRYPTED'
            }
        )

        $MappingFieldMigrate = Get-CIPPAzDataTableEntity @CIPPMapping -Filter "PartitionKey eq 'NinjaFieldMapping'" | ForEach-Object {
            [PSCustomObject]@{
                PartitionKey    = 'NinjaOneFieldMapping'
                RowKey          = $_.RowKey
                IntegrationId   = $_.NinjaOne
                IntegrationName = $_.NinjaOneName
            }
            Remove-CIPPAzDataTableEntity -Force @CIPPMapping -Entity $_
        }
        if (($MappingFieldMigrate | Measure-Object).count -gt 0) {
            Add-CIPPAzDataTableEntity @CIPPMapping -Entity $MappingFieldMigrate -Force
        }

        $Mappings = Get-ExtensionMapping -Extension 'NinjaOneField'

        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).NinjaOne

        $Token = Get-NinjaOneToken -configuration $Configuration

        $NinjaCustomFieldsNodeRaw = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/device-custom-fields?scopes=node" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100

        [System.Collections.Generic.List[object]]$NinjaCustomFieldsNode = $NinjaCustomFieldsNodeRaw | Where-Object { $_.apiPermission -in 'READ_WRITE', 'WRITE_ONLY' -and $_.type -in $CIPPFields.Type } | Select-Object @{n = 'name'; e = { $_.label } }, @{n = 'value'; e = { $_.name } }, type, @{n = 'FieldType'; e = { 'Device' } }

        $NinjaCustomFieldsOrgRaw = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/device-custom-fields?scopes=organization" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100

        [System.Collections.Generic.List[object]]$NinjaCustomFieldsOrg = $NinjaCustomFieldsOrgRaw | Where-Object { $_.apiPermission -in 'READ_WRITE', 'WRITE_ONLY' -and $_.type -in $CIPPFields.Type } | Select-Object @{n = 'name'; e = { $_.label } }, @{n = 'value'; e = { $_.name } }, type, @{n = 'FieldType'; e = { 'Organization' } }

        if ($Null -eq $NinjaCustomFieldsNode) {
            [System.Collections.Generic.List[object]]$NinjaCustomFieldsNode = @()
        }

        if ($Null -eq $NinjaCustomFieldsOrg) {
            [System.Collections.Generic.List[object]]$NinjaCustomFieldsOrg = @()
        }

    } catch {
        Write-Information "Get-NinjaOneFieldMapping: failed to retrieve NinjaOne custom fields: $($_.Exception.Message)"
        [System.Collections.Generic.List[object]]$NinjaCustomFieldsNode = @()
        [System.Collections.Generic.List[object]]$NinjaCustomFieldsOrg = @()
    }

    # Write-only fields are absent from the NinjaOne listing, so mapped ones are kept as options or the page would drop them.
    $Listed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Field in $NinjaCustomFieldsOrg) { [void]$Listed.Add([string]$Field.value) }
    foreach ($Field in $NinjaCustomFieldsNode) { [void]$Listed.Add([string]$Field.value) }
    foreach ($Mapping in @($Mappings)) {
        if (-not [string]::IsNullOrEmpty($Mapping.IntegrationId) -and $Listed.Add([string]$Mapping.IntegrationId)) {
            $NinjaCustomFieldsNode.Add([PSCustomObject]@{ name = $Mapping.IntegrationName; value = $Mapping.IntegrationId; type = 'WRITE_ONLY'; FieldType = 'Device' })
        }
    }

    $MappingObj = [PSCustomObject]@{
        CIPPFields        = $CIPPFields
        CIPPFieldHeaders  = $CIPPFieldHeaders
        IntegrationFields = @($Unset) + @($NinjaCustomFieldsOrg) + @($NinjaCustomFieldsNode)
        Mappings          = @($Mappings)
    }

    return $MappingObj

}
