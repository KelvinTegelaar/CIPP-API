    using namespace System.Net

    Function Invoke-AddExConnector {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        $APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$ConnectorType = ($Request.body.PowerShellCommand | ConvertFrom-Json).cippConnectorType
$RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, cippConnectorType, comments

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$Result = foreach ($Tenantfilter in $tenants) {
    try {
        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "New-$($ConnectorType)connector" -cmdParams $RequestParams 
        "Successfully created transport rule for $tenantfilter."
        Write-LogMessage -API $APINAME -tenant $tenantfilter -message "Created transport rule for $($tenantfilter)" -sev Debug
    }
    catch {
        "Could not create created transport rule for $($tenantfilter): $($_.Exception.message)"
    }
}
 

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{Results = @($Result) }
    })

    }
