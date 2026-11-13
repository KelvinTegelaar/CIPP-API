function Invoke-RemoveGSAFilteringPolicy {
    <#
    .SYNOPSIS
        Deletes a Global Secure Access filtering policy from a tenant
    .DESCRIPTION
        Deletes the filtering policy. Refused while a security profile links it; unlink it from those
        profiles first.
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
    # The id of the filtering policy to delete
    $ID = [string]$Request.Body.ID
    if ($ID -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ID must be the id (a GUID) of the object to delete' } })
    }

    $Graph = 'https://graph.microsoft.com/beta/networkAccess'
    try {
        $Profiles = @(New-GraphGetRequest -uri "$Graph/filteringProfiles?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true)
        $LinkedBy = @($Profiles.Where({ @($_.policies).Where({ $_.policy.id -eq $ID }).Count }).ForEach({ $_.name }))
        if ($LinkedBy.Count) {
            throw [System.ArgumentException]::new("The filtering policy is linked by security profiles: $($LinkedBy -join ', '). Unlink it from them first.")
        }
        $null = New-GraphPOSTRequest -uri "$Graph/filteringPolicies/$ID" -tenantid $TenantFilter -AsApp $true -type DELETE -body ''
        $Result = "Deleted filtering policy $ID"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to delete filtering policy $($ID): $(Get-NormalizedError -Message $_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
}
