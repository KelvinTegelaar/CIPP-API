function Get-NinjaOneFieldMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    try {
        #Get available mappings
        $Mappings = [pscustomobject]@{}

        [System.Collections.Generic.List[PSCustomObject]]$CIPPFields = @(
            [PSCustomObject]@{
                InternalName = 'TenantLinks'
                Description  = 'Microsoft 365 Tenant Links - Field Used to Display Links to Microsoft 365 Portals and CIPP'
                Scope        = 'Organization'
                Type         = 'WYSIWYG'
            },
            [PSCustomObject]@{
                InternalName = 'TenantSummary'
                Description  = 'Microsoft 365 Tenant Summary - Field Used to Display Tenant Summary Information'
                Scope        = 'Organization'
                Type         = 'WYSIWYG'
            },
            [PSCustomObject]@{
                InternalName = 'UsersSummary'
                Description  = 'Microsoft 365 Users Summary - Field Used to Display User Summary Information'
                Scope        = 'Organization'
                Type         = 'WYSIWYG'
            },
            [PSCustomObject]@{
                InternalName = 'DeviceLinks'
                Description  = 'Microsoft 365 Device Links - Field Used to Display Links to Microsoft 365 Portals and CIPP'
                Scope        = 'Device'
                Type         = 'WYSIWYG'
            },
            [PSCustomObject]@{
                InternalName = 'DeviceSummary'
                Description  = 'Microsoft 365 Device Summary - Field Used to Display Device Summary Information'
                Scope        = 'Device'
                Type         = 'WYSIWYG'
            },
            [PSCustomObject]@{
                InternalName = 'DeviceCompliance'
                Description  = 'Intune Device Compliance Status - Field Used to Monitor Device Compliance'
                Scope        = 'Device'
                Type         = 'TEXT'
            }
        )

        $Filter = "PartitionKey eq 'NinjaFieldMapping'"
        Get-AzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
            $Mappings | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue @{ label = "$($_.NinjaOneName)"; value = "$($_.NinjaOne)" }
        }


        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).NinjaOne
    

    
        $Token = Get-NinjaOneToken -configuration $Configuration
    
        $NinjaCustomFieldsNodeRaw = (Invoke-WebRequest -uri "https://$($Configuration.Instance)/api/v2/device-custom-fields?scopes=node" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -depth 100
        [System.Collections.Generic.List[PSCustomObject]]$NinjaCustomFieldsNode = $NinjaCustomFieldsNodeRaw | Where-Object { $_.apiPermission -eq 'READ_WRITE' -and $_.type -in $CIPPFields.Type } | Select-Object @{n = 'name'; e = { $_.label } }, @{n = 'value'; e = { $_.name } }, type
    
        $NinjaCustomFieldsOrgRaw = (Invoke-WebRequest -uri "https://$($Configuration.Instance)/api/v2/device-custom-fields?scopes=organization" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -depth 100
        [System.Collections.Generic.List[PSCustomObject]]$NinjaCustomFieldsOrg = $NinjaCustomFieldsOrgRaw | Where-Object { $_.apiPermission -eq 'READ_WRITE' -and $_.type -in $CIPPFields.Type } | Select-Object @{n = 'name'; e = { $_.label } }, @{n = 'value'; e = { $_.name } }, type

        if ($Null -eq $NinjaCustomFieldsNode){
            [System.Collections.Generic.List[PSCustomObject]]$NinjaCustomFieldsNode = @()
        }
        
        if ($Null -eq $NinjaCustomFieldsOrg){
            [System.Collections.Generic.List[PSCustomObject]]$NinjaCustomFieldsOrg = @()
        }
        
    } catch {
        [System.Collections.Generic.List[PSCustomObject]]$NinjaCustomFieldsNode = @()
        [System.Collections.Generic.List[PSCustomObject]]$NinjaCustomFieldsOrg = @()
    }

    $DoNotSync = [PSCustomObject]@{
        name  = '--- Do not synchronize ---'
        value = $null
        type  = 'unset'
    }

    $NinjaCustomFieldsOrg.Insert(0, $DoNotSync)
    $NinjaCustomFieldsNode.Insert(0, $DoNotSync)


    $MappingObj = [PSCustomObject]@{
        CIPPOrgFields   = $CIPPFields | Where-Object { $_.Scope -eq 'Organization' }
        CIPPNodeFields  = @($CIPPFields | Where-Object { $_.Scope -eq 'Device' })
        NinjaOrgFields  = @($NinjaCustomFieldsOrg)
        NinjaNodeFields = @($NinjaCustomFieldsNode)
        Mappings        = $Mappings
    }

    return $MappingObj

}