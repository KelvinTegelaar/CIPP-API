function Set-NinjaOneFieldMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )
    
    $SettingsTable = Get-CIPPTable -TableName NinjaOneSettings
    $AddObject = @{
        PartitionKey   = 'NinjaConfig'
        RowKey         = 'CIPPURL'
        'SettingValue' = ($Request.Url -split '/')[2]
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