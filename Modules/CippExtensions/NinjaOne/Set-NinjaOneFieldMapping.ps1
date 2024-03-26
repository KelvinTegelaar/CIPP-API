function Set-NinjaOneFieldMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request,
        $TriggerMetadata
    )
    
    $SettingsTable = Get-CIPPTable -TableName NinjaOneSettings
    $AddObject = @{
        PartitionKey   = 'NinjaConfig'
        RowKey         = 'CIPPURL'
        'SettingValue' = ([System.Uri]$TriggerMetadata.Headers.referer).Host
    }
    Add-AzDataTableEntity @SettingsTable -Entity $AddObject -Force

    foreach ($Mapping in ([pscustomobject]$Request.body.mappings).psobject.properties) {
        $AddObject = @{
            PartitionKey   = 'NinjaFieldMapping'
            RowKey         = "$($mapping.name)"
            'NinjaOne'     = "$($mapping.value.value)"
            'NinjaOneName' = "$($mapping.value.label)"
        }
        Add-AzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added mapping for $($mapping.name)." -Sev 'Info' 
    }
    $Result = [pscustomobject]@{'Results' = "Successfully edited mapping table." }

    Return $Result
}