function Sync-CIPPGSAFilteringProfile {
    <#
    .SYNOPSIS
        Deploys a Global Secure Access security profile template, and the filtering policy
        templates it links, to a tenant.
    .DESCRIPTION
        Reads the tenant live, compares with Compare-CIPPGSAFilteringProfile and refuses with an
        ArgumentException when anything conflicts. Otherwise creates or updates the policies,
        then the profile, then its links, and removes links the template does not have. Policies
        and profiles are never deleted. Returns the tenant profile id and one result per write.
        The caller checks the Internet Access licence.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ProfileTemplate,
        [hashtable]$PolicyTemplates = @{},
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Graph = 'https://graph.microsoft.com/beta/networkAccess'
    $Rows = [System.Collections.Generic.List[object]]::new()
    foreach ($Row in @(New-GraphGetRequest -uri "$Graph/filteringProfiles?`$expand=policies(`$expand=policy),conditionalAccessPolicies" -tenantid $TenantFilter -AsApp $true)) {
        $Row.PSObject.Properties.Add([psnoteproperty]::new('kind', 'profile'))
        $Rows.Add($Row)
    }
    foreach ($Row in @(New-GraphGetRequest -uri "$Graph/filteringPolicies?`$expand=policyRules" -tenantid $TenantFilter -AsApp $true)) {
        $Row.PSObject.Properties.Add([psnoteproperty]::new('kind', 'policy'))
        $Rows.Add($Row)
    }
    $Categories = @(New-GraphGetRequest -uri "$Graph/connectivity/webCategories" -tenantid $TenantFilter -AsApp $true)

    $Findings = @(Compare-CIPPGSAFilteringProfile -ProfileTemplate $ProfileTemplate -PolicyTemplates $PolicyTemplates -TenantRows @($Rows) -WebCategories $Categories)
    $Conflicts = $Findings.Where({ $_.state -eq 'conflict' })
    if ($Conflicts.Count) {
        throw [System.ArgumentException]::new("Cannot deploy security profile '$($ProfileTemplate.name)': " + (@($Conflicts.ForEach({ "$($_.object) '$($_.name)' - $($_.detail)" })) -join '; '))
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    $PolicyIds = @{}
    foreach ($Link in @($ProfileTemplate.policies)) {
        $Template = $PolicyTemplates[[string]$Link.policy.value]
        $Finding = $Findings.Where({ $_.object -eq 'policy' -and $_.name -eq $Template.name }, 'First')[0]
        # An existing policy keeps its id, and so its link, even when updating it fails.
        $PolicyIds[$Template.name] = $Finding.id
        if ($Finding.state -eq 'match') { continue }
        try {
            $Current = if ($Finding.id) { $Rows.Where({ $_.id -eq $Finding.id }, 'First')[0] }
            $PolicyIds[$Template.name] = Set-CIPPGSAFilteringPolicy -TenantFilter $TenantFilter -Policy $Template -Current $Current
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = if ($Finding.state -eq 'missing') { "Created filtering policy '$($Template.name)'" } else { "Updated filtering policy '$($Template.name)': $($Finding.detail)" } })
        } catch {
            $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to deploy filtering policy '$($Template.name)': $(Get-NormalizedError -Message $_.Exception.Message)" })
        }
    }

    $ProfileFinding = $Findings.Where({ $_.object -eq 'profile' }, 'First')[0]
    $ProfileId = $ProfileFinding.id
    try {
        if ($ProfileFinding.state -eq 'missing') {
            $Body = ConvertTo-Json -Compress -InputObject ([ordered]@{ name = $ProfileTemplate.name; description = $ProfileTemplate.description; state = $ProfileTemplate.state; priority = [int64]$ProfileTemplate.priority; policies = @() })
            $ProfileId = (New-GraphPOSTRequest -uri "$Graph/filteringProfiles" -tenantid $TenantFilter -AsApp $true -type POST -body $Body).id
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Created security profile '$($ProfileTemplate.name)'" })
        } elseif ($ProfileFinding.state -eq 'drift') {
            $Body = ConvertTo-Json -Compress -InputObject ([ordered]@{ description = $ProfileTemplate.description; state = $ProfileTemplate.state; priority = [int64]$ProfileTemplate.priority })
            $null = New-GraphPOSTRequest -uri "$Graph/filteringProfiles/$ProfileId" -tenantid $TenantFilter -AsApp $true -type PATCH -body $Body
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Updated security profile '$($ProfileTemplate.name)': $($ProfileFinding.detail)" })
        }
    } catch {
        $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to deploy security profile '$($ProfileTemplate.name)': $(Get-NormalizedError -Message $_.Exception.Message)" })
        return [pscustomobject]@{ ProfileId = $null; Results = @($Results) }
    }

    $Wanted = foreach ($Link in @($ProfileTemplate.policies)) {
        $PolicyName = $PolicyTemplates[[string]$Link.policy.value].name
        if (-not $PolicyIds[$PolicyName]) {
            $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Did not link '$PolicyName' because the policy failed to deploy" })
            continue
        }
        [pscustomobject]@{ policyId = $PolicyIds[$PolicyName]; policyName = $PolicyName; priority = $Link.priority; state = $Link.state; loggingState = $Link.loggingState ?? 'enabled' }
    }
    $CurrentLinks = $Rows.Where({ $_.kind -eq 'profile' -and $_.id -eq $ProfileId }, 'First')[0].policies
    foreach ($Item in @(Set-CIPPGSAProfileLinks -TenantFilter $TenantFilter -ProfileId $ProfileId -ProfileName $ProfileTemplate.name -Links $Wanted -Current $CurrentLinks)) { $Results.Add($Item) }

    [pscustomobject]@{ ProfileId = $ProfileId; Results = @($Results) }
}
