using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$Table = Get-CIPPTable -TableName CippMapping
try {
    
    if ($Request.Query.List) {
        #Get available mappings
        $Mappings = Get-AzDataTableEntity @Table
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
                label = $_.name
                value = $_.id
            }
        }
        $MappingObj = [PSCustomObject]@{
            Tenants     = $Tenants
            HaloClients = $HaloClients
            Mappings    = $Mappings
        }
        $body = @($MappingObj)
    }

    # Interact with query parameters or the body of the request.
    if ($Request.Query.AddMapping) {
        $AddObject = @{
            PartitionKey = 'Mapping'
            RowKey       = $Request.body.TenantId
            'HaloPSA'    = $Request.body.HaloPSAId
        }
        Add-AzDataTableEntity @Table -Entity $AddObject -Force
        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added mapping $($request.body.SKUName)" -Sev 'Info' 
        $body = [pscustomobject]@{'Results' = "Success. We've added $($request.body.SKUName) to the excluded list." }
    }

    if ($Request.Query.RemoveMapping) {
        $Filter = "RowKey eq '{0}' and PartitionKey eq 'Mapping'" -f $Request.Query.TenantId
        $Entity = Get-AzDataTableEntity @Table -Filter $Filter
        Remove-AzDataTableEntity @Table -Entity $Entity
        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Removed mapping $($Request.Query.TenantId)" -Sev 'Info'
        $body = [pscustomobject]@{'Results' = "Success. We've removed $($Request.query.guid) from the excluded list." }
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
