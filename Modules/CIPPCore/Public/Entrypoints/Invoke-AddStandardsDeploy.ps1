    using namespace System.Net

    Function Invoke-AddStandardsDeploy {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        $APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$user = $request.headers.'x-ms-client-principal'
$username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails

try {
    $Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
    $Settings = ($request.body | Select-Object -Property * -ExcludeProperty Select_*, None )
    foreach ($Tenant in $tenants) {
        
        $object = [PSCustomObject]@{
            Tenant    = $tenant
            AddedBy   = $username
            AppliedAt = (Get-Date).ToString('s')
            Standards = $Settings
        } | ConvertTo-Json -Depth 10
        $Table = Get-CippTable -tablename 'standards'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$object"
            RowKey       = "$Tenant"
            PartitionKey = "standards"
        }
    }
    $body = [pscustomobject]@{"Results" = "Successfully added standards deployment" }
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME -message "Standards API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to add standard: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

    }
