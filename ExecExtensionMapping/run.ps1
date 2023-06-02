using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$Table = Get-CIPPTable -TableName CippMapping

if ($Request.Query.List) {
    #Get available mappings
    $Mappings = [pscustomobject]@{}
    Get-AzDataTableEntity @Table | ForEach-Object {
        $Mappings | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue @{ label = "$($_.HaloPSAName)"; value = "$($_.HaloPSA)" }
    }
    #Get Available TEnants
    $Tenants = Get-Tenants
    #Get available halo clients
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json).HaloPSA
    $Token = Get-HaloToken -configuration $Configuration
    $i = 0
    $RawHaloClients = do {
        $Result = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Client?page_no=$i&page_size=999" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" }
        $Result.clients | Select-Object * -ExcludeProperty logo
        $i++
        $pagecount = [Math]::Ceiling($Result.record_count / 999)
    } while ($i -le $pagecount)
    $HaloClients = $RawHaloClients | ForEach-Object {
        [PSCustomObject]@{
            name  = $_.name
            value = "$($_.id)"
        }
    }
    $MappingObj = [PSCustomObject]@{
        Tenants     = @($Tenants)
        HaloClients = @($HaloClients)
        Mappings    = $Mappings
    }
    $body = $MappingObj
}
try {
    if ($Request.Query.AddMapping) {
        foreach ($Mapping in ([pscustomobject]$Request.body.mappings).psobject.properties) {
            $AddObject = @{
                PartitionKey  = 'Mapping'
                RowKey        = "$($mapping.name)"
                'HaloPSA'     = "$($mapping.value.value)"
                'HaloPSAName' = "$($mapping.value.label)"
            }
            Add-AzDataTableEntity @Table -Entity $AddObject -Force
            Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added mapping for $($mapping.name)." -Sev 'Info' 
        }
        $body = [pscustomobject]@{'Results' = "Successfully edited mapping table." }
    }
}
catch {
    Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "mapping API failed. $($_.Exception.Message)" -Sev 'Error'
    $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
