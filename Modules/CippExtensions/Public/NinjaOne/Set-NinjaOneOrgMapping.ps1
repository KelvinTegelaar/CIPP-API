function Set-NinjaOneOrgMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )

    Get-CIPPAzDataTableEntity @CIPPMapping -Filter "PartitionKey eq 'NinjaOneMapping'" | ForEach-Object {
        Remove-AzDataTableEntity -Force @CIPPMapping -Entity $_
    }
    foreach ($Mapping in ([pscustomobject]$Request.body.mappings).psobject.properties) {
        $AddObject = @{
            PartitionKey    = 'NinjaOneMapping'
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