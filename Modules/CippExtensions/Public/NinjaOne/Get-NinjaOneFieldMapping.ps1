function Get-NinjaOneFieldMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
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
                Description = 'Use the table below to map your Device Field to the correct NinjaOne Field'
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
            }
        )

        $MappingFieldMigrate = Get-CIPPAzDataTableEntity @CIPPMapping -Filter "PartitionKey eq 'NinjaFieldMapping'" | ForEach-Object {
            [PSCustomObject]@{
                PartitionKey    = 'NinjaOneFieldMapping'
                RowKey          = $_.RowKey
                IntegrationId   = $_.NinjaOne
                IntegrationName = $_.NinjaOneName
            }
            Remove-AzDataTableEntity @CIPPMapping -Entity $_
        }
        if (($MappingFieldMigrate | Measure-Object).count -gt 0) {
            Add-CIPPAzDataTableEntity @CIPPMapping -Entity $MappingFieldMigrate -Force
        }

        $Mappings = Get-ExtensionMapping -Extension 'NinjaOneField'

        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).NinjaOne

        $Token = Get-NinjaOneToken -configuration $Configuration

        $NinjaCustomFieldsNodeRaw = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/device-custom-fields?scopes=node" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100

        [System.Collections.Generic.List[object]]$NinjaCustomFieldsNode = $NinjaCustomFieldsNodeRaw | Where-Object { $_.apiPermission -eq 'READ_WRITE' -and $_.type -in $CIPPFields.Type } | Select-Object @{n = 'name'; e = { $_.label } }, @{n = 'value'; e = { $_.name } }, type, @{n = 'FieldType'; e = { 'Device' } }

        $NinjaCustomFieldsOrgRaw = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/device-custom-fields?scopes=organization" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100

        [System.Collections.Generic.List[object]]$NinjaCustomFieldsOrg = $NinjaCustomFieldsOrgRaw | Where-Object { $_.apiPermission -eq 'READ_WRITE' -and $_.type -in $CIPPFields.Type } | Select-Object @{n = 'name'; e = { $_.label } }, @{n = 'value'; e = { $_.name } }, type, @{n = 'FieldType'; e = { 'Organization' } }

        if ($Null -eq $NinjaCustomFieldsNode) {
            [System.Collections.Generic.List[object]]$NinjaCustomFieldsNode = @()
        }

        if ($Null -eq $NinjaCustomFieldsOrg) {
            [System.Collections.Generic.List[object]]$NinjaCustomFieldsOrg = @()
        }
        $Unset = [PSCustomObject]@{
            name  = '--- Do not synchronize ---'
            value = $null
            type  = 'unset'
        }

    } catch {
        [System.Collections.Generic.List[object]]$NinjaCustomFieldsNode = @()
        [System.Collections.Generic.List[objecgt]]$NinjaCustomFieldsOrg = @()
    }

    $MappingObj = [PSCustomObject]@{
        CIPPFields        = $CIPPFields
        CIPPFieldHeaders  = $CIPPFieldHeaders
        IntegrationFields = @($Unset) + @($NinjaCustomFieldsOrg) + @($NinjaCustomFieldsNode)
        Mappings          = $Mappings
    }

    return $MappingObj

}