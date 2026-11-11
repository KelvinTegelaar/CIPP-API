function Invoke-ListGSAFilteringPolicies {
    <#
    .SYNOPSIS
        Lists a tenant's Global Secure Access web content filtering policies
    .DESCRIPTION
        Returns the tenant's filtering policies with their rules, read live, and the names of the
        security profiles that link each one.
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
        $LinkedBy = @{}
        foreach ($FilteringProfile in @(New-GraphGetRequest -uri "$Graph/filteringProfiles?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true)) {
            foreach ($Link in @($FilteringProfile.policies)) {
                $PolicyId = [string]$Link.policy.id
                if (-not $LinkedBy.ContainsKey($PolicyId)) { $LinkedBy[$PolicyId] = [System.Collections.Generic.List[string]]::new() }
                $LinkedBy[$PolicyId].Add($FilteringProfile.name)
            }
        }
        $Body = @(foreach ($Policy in @(New-GraphGetRequest -uri "$Graph/filteringPolicies?`$expand=policyRules" -tenantid $TenantFilter -AsApp $true)) {
                $ProfileNames = $LinkedBy[[string]$Policy.id]
                if ($null -eq $ProfileNames) { $ProfileNames = [string[]]@() }
                $Policy.PSObject.Properties.Add([psnoteproperty]::new('securityProfiles', [string[]]$ProfileNames))
                $Policy
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = @{ Results = "Failed to list filtering policies: $(Get-NormalizedError -Message $_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = $Body })
}
