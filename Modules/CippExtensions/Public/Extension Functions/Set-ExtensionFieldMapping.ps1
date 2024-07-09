function Set-ExtensionFieldMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $Extension,
        $APIName,
        $Request,
        $TriggerMetadata
    )

    foreach ($Mapping in ([pscustomobject]$Request.body.mappings).psobject.properties) {
        $AddObject = @{
            PartitionKey    = "$($Extension)FieldMapping"
            RowKey          = "$($mapping.name)"
            IntegrationId   = "$($mapping.value.value)"
            IntegrationName = "$($mapping.value.label)"
        }
        Add-AzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added mapping for $($mapping.name)." -Sev 'Info'
    }
    $Result = [pscustomobject]@{'Results' = 'Successfully edited mapping table.' }

    Return $Result
}