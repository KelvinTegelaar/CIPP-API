function Set-HaloMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )
    Get-CIPPAzDataTableEntity @CIPPMapping -Filter "PartitionKey eq 'HaloMapping'" | ForEach-Object {
        Remove-AzDataTableEntity -Force @CIPPMapping -Entity $_
    }
    foreach ($Mapping in $Request.Body) {
        $AddObject = @{
            PartitionKey    = 'HaloMapping'
            RowKey          = "$($mapping.TenantId)"
            IntegrationId   = "$($mapping.IntegrationId)"
            IntegrationName = "$($mapping.IntegrationName)"
        }

        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force

        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added mapping for $($mapping.name)." -Sev 'Info'
    }
    $Result = [pscustomobject]@{'Results' = 'Successfully edited mapping table.' }

    Return $Result
}
