function Invoke-EditGSAFilteringPolicy {
    <#
    .SYNOPSIS
        Creates or edits a Global Secure Access filtering policy in a tenant
    .DESCRIPTION
        Creates a filtering policy when no ID is sent, or changes an existing one's name, action, description
        and rules. Rules are matched on type and destinations, so rules that did not change are left alone.
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
    # The id of the filtering policy to edit; leave it out to create a new policy
    $ID = [string]$Request.Body.ID
    $Name = ([string]$Request.Body.name).Trim()

    $Errors = [System.Collections.Generic.List[string]]::new()
    if ($ID -and $ID -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { $Errors.Add('ID must be the id (a GUID) of the filtering policy') }
    if (-not $Name) { $Errors.Add('name is required') }
    switch ($Request.Body.action) {
        'block' {}
        'allow' {}
        default { $Errors.Add("action must be block or allow, not '$($Request.Body.action)'") }
    }
    # Each rule: a name, a ruleType (webCategory, fqdn or url) and its destinations, as names/values or Graph destination objects
    $Converted = ConvertTo-CIPPGSAFilteringRule -Rules $Request.Body.policyRules
    foreach ($ErrorText in $Converted.Errors) { $Errors.Add($ErrorText) }
    if ($Errors.Count) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Invalid filtering policy: $($Errors -join '; ')" } })
    }

    try {
        $Current = $null
        if ($ID) {
            $Current = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/networkAccess/filteringPolicies/$($ID)?`$expand=policyRules" -tenantid $TenantFilter -AsApp $true
        } elseif (@(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/filteringPolicies' -tenantid $TenantFilter -AsApp $true).Where({ $_.name -eq $Name }).Count) {
            throw [System.ArgumentException]::new("A filtering policy named '$Name' already exists in this tenant")
        }
        $Policy = [pscustomobject]@{ name = $Name; description = [string]$Request.Body.description; action = [string]$Request.Body.action; policyRules = $Converted.Rules }
        $null = Set-CIPPGSAFilteringPolicy -TenantFilter $TenantFilter -Policy $Policy -Current $Current
        $Result = "$($ID ? 'Updated' : 'Created') filtering policy '$Name'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to $($ID ? 'update' : 'create') filtering policy '$Name': $(Get-NormalizedError -Message $_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
}
