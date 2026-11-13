function Set-CIPPGSAFilteringPolicy {
    <#
    .SYNOPSIS
        Creates a Global Secure Access filtering policy, or brings an existing one in line.
    .DESCRIPTION
        Policy is the desired policy in Graph shape (name, description, action, policyRules). Without
        Current it is created. With Current (the tenant policy, policyRules expanded) the name, action
        and description are patched and the rules converged one at a time, because Graph refuses to
        patch policyRules on the policy: rules not wanted are deleted, missing ones added, and rules
        are matched on type and destinations, not on name. Returns the policy id; throws on failure.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        $Policy,
        $Current
    )

    $Graph = 'https://graph.microsoft.com/beta/networkAccess'
    $Rules = @(@($Policy.policyRules).ForEach({
                $Rule = $_
                [ordered]@{
                    '@odata.type' = $Rule.'@odata.type'
                    name          = $Rule.name
                    ruleType      = $Rule.ruleType
                    destinations  = @(@($Rule.destinations).ForEach({ if ($Rule.ruleType -eq 'webCategory') { [ordered]@{ '@odata.type' = $_.'@odata.type'; name = $_.name } } else { [ordered]@{ '@odata.type' = $_.'@odata.type'; value = $_.value } } }))
                }
            }))

    if (-not $Current) {
        $Body = ConvertTo-Json -Depth 10 -Compress -InputObject ([ordered]@{ name = $Policy.name; description = $Policy.description; action = $Policy.action; policyRules = $Rules })
        return (New-GraphPOSTRequest -uri "$Graph/filteringPolicies" -tenantid $TenantFilter -AsApp $true -type POST -body $Body).id
    }

    $Body = ConvertTo-Json -Compress -InputObject ([ordered]@{ name = $Policy.name; action = $Policy.action; description = $Policy.description })
    $null = New-GraphPOSTRequest -uri "$Graph/filteringPolicies/$($Current.id)" -tenantid $TenantFilter -AsApp $true -type PATCH -body $Body
    $Wanted = @{}
    foreach ($Rule in $Rules) { $Wanted["$($Rule.ruleType): " + ((@($Rule.destinations).ForEach({ $_.name ?? $_.value }) | Sort-Object) -join ', ')] = $Rule }
    foreach ($Rule in @($Current.policyRules)) {
        $Key = "$($Rule.ruleType): " + ((@($Rule.destinations).ForEach({ $_.name ?? $_.value }) | Sort-Object) -join ', ')
        if ($Wanted.ContainsKey($Key)) { $Wanted.Remove($Key) } else {
            $null = New-GraphPOSTRequest -uri "$Graph/filteringPolicies/$($Current.id)/policyRules/$($Rule.id)" -tenantid $TenantFilter -AsApp $true -type DELETE -body ''
        }
    }
    foreach ($Rule in $Wanted.Values) {
        $null = New-GraphPOSTRequest -uri "$Graph/filteringPolicies/$($Current.id)/policyRules" -tenantid $TenantFilter -AsApp $true -type POST -body (ConvertTo-Json -Depth 10 -Compress -InputObject $Rule)
    }
    $Current.id
}
