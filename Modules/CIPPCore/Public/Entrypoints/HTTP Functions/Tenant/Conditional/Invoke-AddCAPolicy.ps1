using namespace System.Net

function Invoke-AddCAPolicy {
    <#
    .SYNOPSIS
    Add Conditional Access policies to Microsoft 365 tenants
    
    .DESCRIPTION
    Creates new Conditional Access policies in Microsoft 365 tenants with support for multiple tenants and policy templates
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
        
    .NOTES
    Group: Conditional Access
    Summary: Add CA Policy
    Description: Creates new Conditional Access policies using templates or raw JSON configuration with support for multiple tenant deployment
    Tags: Conditional Access,Policy,Administration
    Parameter: tenantFilter.value (array) [body] - Array of tenant identifiers to deploy policies to
    Parameter: replacename (string) [body] - Pattern to replace in policy names and descriptions
    Parameter: overwrite (boolean) [body] - Whether to overwrite existing policies with the same name
    Parameter: NewState (string) [body] - State of the new policy: enabled, disabled, or enabledForReportingButNotEnforced
    Parameter: RawJSON (object) [body] - Raw JSON configuration for the Conditional Access policy
    Response: Returns a response object with the following properties:
    Response: - Results (array): Array of result messages indicating success or failure for each tenant
    Response: Example: {
      "Results": [
        "Successfully created Conditional Access policy 'Require MFA for all users' in contoso.onmicrosoft.com",
        "Successfully created Conditional Access policy 'Require MFA for all users' in fabrikam.onmicrosoft.com"
      ]
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Tenants = $Request.body.tenantFilter.value
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }

    $results = foreach ($Tenant in $tenants) {
        try {
            $CAPolicy = New-CIPPCAPolicy -replacePattern $Request.Body.replacename -Overwrite $request.Body.overwrite -TenantFilter $Tenant -state $Request.Body.NewState -RawJSON $Request.Body.RawJSON -APIName $APIName -Headers $Headers
            "$CAPolicy"
        }
        catch {
            "$($_.Exception.Message)"
            continue
        }

    }

    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
