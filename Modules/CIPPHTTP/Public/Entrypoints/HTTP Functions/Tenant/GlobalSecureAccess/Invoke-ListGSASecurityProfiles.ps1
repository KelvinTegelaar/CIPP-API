function Invoke-ListGSASecurityProfiles {
    <#
    .SYNOPSIS
        Lists a tenant's Global Secure Access security profiles
    .DESCRIPTION
        Returns the tenant's security profiles, read live, with the filtering policies each one links
        and the Conditional Access policies that apply it.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.GlobalSecureAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $Graph = 'https://graph.microsoft.com/beta/networkAccess'
    try {
        if ((New-GraphGetRequest -uri "$Graph/tenantStatus" -tenantid $TenantFilter -AsApp $true).onboardingStatus -ne 'onboarded') {
            throw [System.ArgumentException]::new('This tenant is not onboarded to Global Secure Access')
        }
        $Body = @(foreach ($FilteringProfile in @(New-GraphGetRequest -uri "$Graph/filteringProfiles?`$expand=policies(`$expand=policy),conditionalAccessPolicies" -tenantid $TenantFilter -AsApp $true)) {
                $FilteringProfile.PSObject.Properties.Add([psnoteproperty]::new('filteringPolicies', [string[]]@(@($FilteringProfile.policies | Sort-Object { [int64]$_.priority }).ForEach({ "$($_.priority): $($_.policy.name)" }))))
                $FilteringProfile.PSObject.Properties.Add([psnoteproperty]::new('conditionalAccessPolicyNames', [string[]]@(@($FilteringProfile.conditionalAccessPolicies).ForEach({ $_.displayName }))))
                $FilteringProfile
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = @{ Results = "Failed to list security profiles: $(Get-NormalizedError -Message $_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = $Body })
}
