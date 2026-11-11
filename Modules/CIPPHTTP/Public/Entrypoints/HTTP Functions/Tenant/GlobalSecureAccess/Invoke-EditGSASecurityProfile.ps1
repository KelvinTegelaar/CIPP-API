function Invoke-EditGSASecurityProfile {
    <#
    .SYNOPSIS
        Creates or edits a Global Secure Access security profile in a tenant
    .DESCRIPTION
        Creates a security profile when no ID is sent, or changes an existing one's name, description,
        priority, state and the filtering policies it links. The built-in baseline profile keeps priority
        65000; editing its links is how a filter applies to all Internet Access traffic without a
        Conditional Access policy.
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
    # The id of the security profile to edit; leave it out to create a new profile
    $ID = [string]$Request.Body.ID
    $Name = ([string]$Request.Body.name).Trim()
    # Processing order, 100-64999; the baseline profile keeps 65000
    $Priority = $Request.Body.priority -as [int]
    $Verb = $ID ? 'update' : 'create'

    $Errors = [System.Collections.Generic.List[string]]::new()
    if ($ID -and $ID -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { $Errors.Add('ID must be the id (a GUID) of the security profile') }
    if (-not $Name) { $Errors.Add('name is required') }
    if ($null -eq $Priority -or $Priority -lt 100 -or $Priority -gt 65000) { $Errors.Add('priority must be a number from 100 to 64999') }
    switch ($Request.Body.state) {
        'enabled' {}
        'disabled' {}
        default { $Errors.Add("state must be enabled or disabled, not '$($Request.Body.state)'") }
    }
    # Each link: policy ({label, value} with the tenant filtering policy id, or the id), priority (100-65000), state and loggingState
    $Converted = ConvertTo-CIPPGSAProfileLink -Links $Request.Body.policies
    foreach ($ErrorText in $Converted.Errors) { $Errors.Add($ErrorText) }
    if ($Errors.Count) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Invalid security profile: $($Errors -join '; ')" } })
    }

    $Graph = 'https://graph.microsoft.com/beta/networkAccess'
    $Results = [System.Collections.Generic.List[object]]::new()
    try {
        $Current = $null
        if ($ID) {
            $Current = New-GraphGetRequest -uri "$Graph/filteringProfiles/$($ID)?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true
        } else {
            $Taken = @(New-GraphGetRequest -uri "$Graph/filteringProfiles" -tenantid $TenantFilter -AsApp $true).Where({ [int64]$_.priority -eq $Priority }, 'First')[0]
            if ($Taken) { throw [System.ArgumentException]::new("Priority $Priority is already used by security profile '$($Taken.name)'") }
        }
        $IsBaseline = $Current -and [int64]$Current.priority -eq 65000
        if ($IsBaseline -and $Priority -ne 65000) { throw [System.ArgumentException]::new('The baseline profile keeps priority 65000') }
        if (-not $IsBaseline -and $Priority -eq 65000) { throw [System.ArgumentException]::new('priority must be a number from 100 to 64999; 65000 belongs to the baseline profile') }
        $PolicyNames = @{}
        foreach ($Policy in @(New-GraphGetRequest -uri "$Graph/filteringPolicies" -tenantid $TenantFilter -AsApp $true)) { $PolicyNames[[string]$Policy.id] = $Policy.name }
        $Missing = @($Converted.Links.Where({ -not $PolicyNames.ContainsKey($_.policy.value) }).ForEach({ $_.policy.label ? "'$($_.policy.label)'" : $_.policy.value }))
        if ($Missing.Count) { throw [System.ArgumentException]::new("these filtering policies do not exist in the tenant: $($Missing -join ', ')") }

        if ($ID) {
            $Body = ConvertTo-Json -Compress -InputObject ([ordered]@{ name = $Name; description = [string]$Request.Body.description; state = [string]$Request.Body.state; priority = $Priority })
            $null = New-GraphPOSTRequest -uri "$Graph/filteringProfiles/$ID" -tenantid $TenantFilter -AsApp $true -type PATCH -body $Body
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Updated security profile '$Name'" })
        } else {
            $Body = ConvertTo-Json -Compress -InputObject ([ordered]@{ name = $Name; description = [string]$Request.Body.description; state = [string]$Request.Body.state; priority = $Priority; policies = @() })
            $ID = (New-GraphPOSTRequest -uri "$Graph/filteringProfiles" -tenantid $TenantFilter -AsApp $true -type POST -body $Body).id
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Created security profile '$Name'" })
        }
        $Wanted = @($Converted.Links.ForEach({ [pscustomobject]@{ policyId = $_.policy.value; policyName = $PolicyNames[$_.policy.value]; priority = $_.priority; state = $_.state; loggingState = $_.loggingState } }))
        foreach ($Item in @(Set-CIPPGSAProfileLinks -TenantFilter $TenantFilter -ProfileId $ID -ProfileName $Name -Links $Wanted -Current @($Current.policies).Where({ $_ }))) { $Results.Add($Item) }
        $Failed = @($Results.Where({ $_.state -eq 'error' })).Count
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Updated security profile '$Name' with $($Results.Count) change(s), $Failed failed" -Sev ($Failed ? 'Warning' : 'Info')
        $StatusCode = Get-CippBulkStatusCode -Total $Results.Count -Failed $Failed
    } catch {
        $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to $Verb security profile '$Name': $(Get-NormalizedError -Message $_.Exception.Message)" })
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to $Verb security profile '$Name': $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = @($Results) } })
}
