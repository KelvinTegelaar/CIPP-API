function Set-SyncroMapping {
    <#
    .SYNOPSIS
        Replaces the stored tenant-to-Syncro-customer mappings with the rows posted from the
        Tenant Mapping tab.
    #>
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )
    Get-CIPPAzDataTableEntity @CIPPMapping -Filter "PartitionKey eq 'SyncroMapping'" | ForEach-Object {
        Remove-CIPPAzDataTableEntity -Force @CIPPMapping -Entity $_
    }
    foreach ($Mapping in $Request.Body) {
        if (-not $Mapping.TenantId) { continue }
        $AddObject = @{
            PartitionKey    = 'SyncroMapping'
            RowKey          = "$($Mapping.TenantId)"
            IntegrationId   = "$($Mapping.IntegrationId)"
            IntegrationName = "$($Mapping.IntegrationName)"
        }

        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API $APIName -headers $Request.Headers -message "Added Syncro mapping for $($Mapping.Tenant) to customer $($Mapping.IntegrationName)." -Sev 'Info'
    }
    $Result = [pscustomobject]@{ 'Results' = 'Successfully edited mapping table.' }

    return $Result
}
