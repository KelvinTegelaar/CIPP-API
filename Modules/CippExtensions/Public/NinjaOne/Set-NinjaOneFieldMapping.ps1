function Set-NinjaOneFieldMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request,
        $TriggerMetadata
    )

    $SettingsTable = Get-CIPPTable -TableName NinjaOneSettings
    foreach ($Mapping in $Request.Body.PSObject.Properties) {
        $AddObject = @{
            PartitionKey    = 'NinjaOneFieldMapping'
            RowKey          = "$($mapping.name)"
            IntegrationId   = "$($mapping.value.value)"
            IntegrationName = "$($mapping.value.label)"
        }

        Add-AzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API $APINAME -headers $Request.Headers -message "Added mapping for $($mapping.name)." -Sev 'Info'
    }
    $Result = [pscustomobject]@{'Results' = 'Successfully edited mapping table.' }

    Return $Result
}
