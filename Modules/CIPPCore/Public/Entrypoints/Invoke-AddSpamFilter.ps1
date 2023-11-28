    using namespace System.Net

    Function Invoke-AddSpamFilter {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, comments

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$Result = foreach ($Tenantfilter in $tenants) {
    try {
        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "New-HostedContentFilterPolicy" -cmdParams $RequestParams
        $Domains = (New-ExoRequest -tenantid $Tenantfilter -cmdlet "Get-AcceptedDomain").name
        $ruleparams = @{
            "name"                      = "$($RequestParams.name)";
            "hostedcontentfilterpolicy" = "$($RequestParams.name)";
            "recipientdomainis"         = @($domains)
            "Enabled"                   = $true
        }
        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "New-HostedContentFilterRule" -cmdParams $ruleparams
        "Successfully created spamfilter for $tenantfilter."
        Write-LogMessage -API $APINAME -tenant $tenantfilter -message "Created spamfilter for $($tenantfilter)" -sev Debug
    }
    catch {
        "Could not create create spamfilter rule for $($tenantfilter): $($_.Exception.message)"
    }
}
 

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{Results = @($Result) }
    })

    }
