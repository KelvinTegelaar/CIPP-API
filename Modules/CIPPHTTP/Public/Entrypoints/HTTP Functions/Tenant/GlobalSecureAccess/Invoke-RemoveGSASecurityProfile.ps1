function Invoke-RemoveGSASecurityProfile {
    <#
    .SYNOPSIS
        Deletes a Global Secure Access security profile from a tenant
    .DESCRIPTION
        Deletes the security profile. Its filtering policies stay in the tenant. Refused for the
        built-in baseline profile and while a Conditional Access policy applies the profile.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.GlobalSecureAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # The id of the security profile to delete
    $ID = [string]$Request.Body.ID
    if ($ID -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ID must be the id (a GUID) of the object to delete' } })
    }

    $Graph = 'https://graph.microsoft.com/beta/networkAccess'
    try {
        $FilteringProfile = New-GraphGetRequest -uri "$Graph/filteringProfiles/$($ID)?`$expand=conditionalAccessPolicies" -tenantid $TenantFilter -AsApp $true
        if ([int64]$FilteringProfile.priority -eq 65000) {
            throw [System.ArgumentException]::new("'$($FilteringProfile.name)' is the tenant's built-in baseline profile and cannot be deleted")
        }
        $CAPolicies = @(@($FilteringProfile.conditionalAccessPolicies).ForEach({ $_.displayName }))
        if ($CAPolicies.Count) {
            throw [System.ArgumentException]::new("'$($FilteringProfile.name)' is applied by Conditional Access policies: $($CAPolicies -join ', '). Remove it from them first.")
        }
        $null = New-GraphPOSTRequest -uri "$Graph/filteringProfiles/$ID" -tenantid $TenantFilter -AsApp $true -type DELETE -body ''
        $Result = "Deleted security profile '$($FilteringProfile.name)'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to delete security profile $($ID): $(Get-NormalizedError -Message $_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
}
