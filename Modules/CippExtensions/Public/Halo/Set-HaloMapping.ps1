function Set-HaloMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )
    Get-CIPPAzDataTableEntity @CIPPMapping -Filter "PartitionKey eq 'Mapping'" | ForEach-Object {
        Remove-AzDataTableEntity @CIPPMapping -Entity $_
    }
    foreach ($Mapping in ([pscustomobject]$Request.body.mappings).psobject.properties) {
        $AddObject = @{
            PartitionKey  = 'Mapping'
            RowKey        = "$($mapping.name)"
            'HaloPSA'     = "$($mapping.value.value)"
            'HaloPSAName' = "$($mapping.value.label)"
        }

        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force

        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added mapping for $($mapping.name)." -Sev 'Info' 
    }
    $Result = [pscustomobject]@{'Results' = 'Successfully edited mapping table.' }

    Return $Result
}