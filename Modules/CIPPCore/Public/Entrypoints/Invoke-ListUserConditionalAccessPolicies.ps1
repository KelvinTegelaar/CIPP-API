using namespace System.Net

Function Invoke-ListUserConditionalAccessPolicies {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $UserID = $Request.Query.UserID

    try {
        $json = '{"conditions":{"users":{"allUsers":2,"included":{"userIds":["' + $UserID + '"],"groupIds":[]},"excluded":{"userIds":[],"groupIds":[]}},"servicePrincipals":{"allServicePrincipals":1,"includeAllMicrosoftApps":false,"excludeAllMicrosoftApps":false,"userActions":[],"stepUpTags":[]},"conditions":{"minUserRisk":{"noRisk":false,"lowRisk":false,"mediumRisk":false,"highRisk":false,"applyCondition":false},"minSigninRisk":{"noRisk":false,"lowRisk":false,"mediumRisk":false,"highRisk":false,"applyCondition":false},"servicePrincipalRiskLevels":{"noRisk":false,"lowRisk":false,"mediumRisk":false,"highRisk":false,"applyCondition":false},"devicePlatforms":{"all":2,"included":{"android":false,"ios":false,"windowsPhone":false,"windows":false,"macOs":false,"linux":false},"excluded":null,"applyCondition":false},"locations":{"applyCondition":true,"includeLocationType":2,"excludeAllTrusted":false},"clientApps":{"applyCondition":false,"specificClientApps":false,"webBrowsers":false,"exchangeActiveSync":false,"onlyAllowSupportedPlatforms":false,"mobileDesktop":false},"clientAppsV2":{"applyCondition":false,"webBrowsers":false,"mobileDesktop":false,"modernAuth":false,"exchangeActiveSync":false,"onlyAllowSupportedPlatforms":false,"otherClients":false},"deviceState":{"includeDeviceStateType":1,"excludeDomainJoionedDevice":false,"excludeCompliantDevice":false,"applyCondition":true}}},"country":"","device":{}}'
        $ConditionalAccessPolicyOutput = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $tenantfilter
    } catch {
        $ConditionalAccessPolicyOutput = @{}
    }

    $GraphRequest = foreach ($cap in $ConditionalAccessPolicyOutput) {
        if ($cap.id -in $UserPolicies.policyId) {
            $temp = [PSCustomObject]@{
                id          = $cap.id
                displayName = $cap.displayName
            }
            $temp
        }
    }

    Write-Host $GraphRequest

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest) 
        })

}
