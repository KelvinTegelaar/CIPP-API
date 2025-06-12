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
        if ($Mapping.TenantId) {
            $AddObject = @{
                PartitionKey    = 'HaloMapping'
                RowKey          = "$($mapping.TenantId)"
                IntegrationId   = "$($mapping.IntegrationId)"
                IntegrationName = "$($mapping.IntegrationName)"
            }
        }

        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API $APINAME -headers $Request.Headers -message "Added mapping for $($mapping.name)." -Sev 'Info'
    }
    $Result = [pscustomobject]@{'Results' = 'Successfully edited mapping table.' }

    Return $Result
}
