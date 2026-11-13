function Invoke-EditGSATrafficForwardingProfile {
    <#
    .SYNOPSIS
        Edits a Global Secure Access traffic forwarding profile in a tenant
    .DESCRIPTION
        Changes only the parts that are sent: the profile state, whether it applies to all users, the exact
        set of users and groups it is assigned to, the exact set of remote networks that use it and, for the
        Internet profile, the exact custom bypass and acquire destinations. Everything is read and checked
        before the first write, and a part that already matches is left alone.
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
    # The id of the traffic forwarding profile
    $ID = [string]$Request.Body.id
    # enabled or disabled
    $State = [string]$Request.Body.state
    # true to apply the profile to all users, false to apply it only to its assigned users and groups
    $AllUsersValue = $Request.Body.assignedToAllUsers
    # The exact users and groups to assign, each { value: principal id, label, type: User or Group }
    $Assignees = $Request.Body.assignees
    # The exact remote network ids that should use this profile
    $RemoteNetworkIds = $Request.Body.remoteNetworks
    $GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'

    $Errors = [System.Collections.Generic.List[string]]::new()
    if ($ID -notmatch $GuidPattern) { $Errors.Add('id must be the id (a GUID) of the traffic forwarding profile') }
    if ($State -and $State -notin 'enabled', 'disabled') { $Errors.Add("state must be enabled or disabled, not '$State'") }
    if ($null -ne $AllUsersValue -and "$AllUsersValue" -notin 'true', 'false') { $Errors.Add('assignedToAllUsers must be true or false') }
    foreach ($Assignee in @($Assignees ?? @()).Where({ "$($_.value)" -notmatch $GuidPattern })) { $Errors.Add("assignee '$($Assignee.label ?? $Assignee.value ?? $Assignee)' needs a value that is a user or group id") }
    $DesiredRules = @{}
    # Internet profile only. Destinations are FQDNs (wildcards allowed), IPv4 addresses, subnets or begin-end
    # ranges; ports are comma-separated ports or ranges, blank for all ports
    foreach ($Kind in @(
            @{ Key = 'customBypass'; Action = 'bypass'; Destinations = $Request.Body.customBypass; Ports = [string]$Request.Body.customBypassPorts }
            @{ Key = 'customAcquire'; Action = 'forward'; Destinations = $Request.Body.customAcquire; Ports = [string]$Request.Body.customAcquirePorts }
        )) {
        if ($null -eq $Kind.Destinations) { continue }
        try {
            $DesiredRules[$Kind.Key] = @(ConvertTo-CIPPGSAForwardingRule -Destinations @($Kind.Destinations) -Action $Kind.Action -Ports $Kind.Ports)
        } catch {
            $Errors.Add("$($Kind.Key): $($_.Exception.Message)")
        }
    }
    if ($Errors.Count) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Invalid traffic forwarding profile edit: $($Errors -join '; ')" } })
    }

    $Graph = 'https://graph.microsoft.com/beta'
    $Results = [System.Collections.Generic.List[object]]::new()
    $Name = $ID
    try {
        $TrafficProfile = New-GraphGetRequest -uri "$Graph/networkAccess/forwardingProfiles/$($ID)?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true
        $Name = $TrafficProfile.name
        $SpId = $TrafficProfile.servicePrincipal.id
        $FinalState = $State ? $State : $TrafficProfile.state
        if ($DesiredRules.Count -and $TrafficProfile.trafficForwardingType -ne 'internet') {
            throw [System.ArgumentException]::new('Custom bypass and acquire rules belong to the Internet profile only')
        }

        $RequiredWrite = $null
        $AssignmentAdds = @()
        $AssignmentRemoves = @()
        if ($null -ne $AllUsersValue -or $null -ne $Assignees) {
            if (-not $SpId) { throw "Traffic profile '$Name' has no app to assign it through" }
            if ($null -ne $AllUsersValue) {
                $Required = "$AllUsersValue" -eq 'false'
                if ([bool](New-GraphGetRequest -uri "$Graph/servicePrincipals/$($SpId)?`$select=appRoleAssignmentRequired" -tenantid $TenantFilter -AsApp $true).appRoleAssignmentRequired -ne $Required) { $RequiredWrite = $Required }
            }
            if ($null -ne $Assignees) {
                $Current = @(New-GraphGetRequest -uri "$Graph/servicePrincipals/$SpId/appRoleAssignedTo?`$select=id,principalId,principalType,principalDisplayName" -tenantid $TenantFilter -AsApp $true).Where({ $_.principalId })
                $CurrentIds = @($Current.ForEach({ "$($_.principalId)" }))
                $Wanted = [ordered]@{}
                foreach ($Assignee in @($Assignees)) { $Wanted["$($Assignee.value)"] = $Assignee }
                $AssignmentAdds = @($Wanted.Values.Where({ $CurrentIds -notcontains "$($_.value)" }))
                $AssignmentRemoves = @($Current.Where({ -not $Wanted.Contains("$($_.principalId)") }))
            }
        }

        $NetworkWrites = @()
        if ($null -ne $RemoteNetworkIds) {
            if ($TrafficProfile.trafficForwardingType -notin 'm365', 'internet') { throw [System.ArgumentException]::new('Remote networks use the Microsoft 365 and Internet profiles only') }
            $WantedNetworks = @(@($RemoteNetworkIds).ForEach({ "$($_.value ?? $_)" }).Where({ $_ }))
            $Networks = @(New-GraphGetRequest -uri "$Graph/networkAccess/connectivity/remoteNetworks?`$expand=forwardingProfiles(`$select=id)" -tenantid $TenantFilter -AsApp $true).Where({ $_.id })
            $Unknown = @($WantedNetworks.Where({ $Networks.id -notcontains $_ }))
            if ($Unknown.Count) { throw [System.Management.Automation.ItemNotFoundException]::new("These remote networks do not exist in the tenant: $($Unknown -join ', ')") }
            $NetworkWrites = @(foreach ($Network in $Networks) {
                    $ProfileIds = @(@($Network.forwardingProfiles).ForEach({ "$($_.id)" }).Where({ $_ }))
                    $Add = $WantedNetworks -contains $Network.id
                    if ($Add -eq ($ProfileIds -contains $ID)) { continue }
                    if ($Add -and $FinalState -ne 'enabled') { throw [System.ArgumentException]::new("Remote network '$($Network.name)' can only use an enabled profile; enable '$Name' first") }
                    $NewIds = @($ProfileIds.Where({ $_ -ne $ID }); if ($Add) { $ID })
                    if ($NewIds.Count -eq 0) { throw [System.ArgumentException]::new("Remote network '$($Network.name)' must keep at least one traffic profile") }
                    [pscustomobject]@{ id = $Network.id; name = $Network.name; add = $Add; profileIds = $NewIds }
                })
        }

        $RuleWrites = @(foreach ($Kind in @(
                    @{ Key = 'customBypass'; Policy = 'Custom bypass' }
                    @{ Key = 'customAcquire'; Policy = 'Custom Acquire' }
                ).Where({ $DesiredRules.ContainsKey($_.Key) })) {
                $PolicyId = @($TrafficProfile.policies).Where({ $_.policy.name -eq $Kind.Policy }, 'First')[0].policy.id
                if (-not $PolicyId) { throw "The Internet profile has no '$($Kind.Policy)' policy" }
                $CurrentRules = @(New-GraphGetRequest -uri "$Graph/networkAccess/forwardingPolicies/$PolicyId/policyRules" -tenantid $TenantFilter -AsApp $true).Where({ $_.id })
                $Desired = $DesiredRules[$Kind.Key]
                $DesiredText = @(ConvertFrom-CIPPGSAForwardingRule -Rules $Desired).ForEach({ "$($_.destination)|$($_.ports)|$($_.protocols)" }) -join "`n"
                $CurrentText = @(ConvertFrom-CIPPGSAForwardingRule -Rules $CurrentRules).ForEach({ "$($_.destination)|$($_.ports)|$($_.protocols)" }) -join "`n"
                if ($DesiredText -ne $CurrentText) { [pscustomobject]@{ policy = $Kind.Policy; policyId = $PolicyId; ruleIds = @($CurrentRules.ForEach({ $_.id })); rules = $Desired } }
            })

        if ($State -and $State -ne $TrafficProfile.state) {
            try {
                $null = New-GraphPOSTRequest -uri "$Graph/networkAccess/forwardingProfiles/$ID" -tenantid $TenantFilter -AsApp $true -type PATCH -body (ConvertTo-Json -Compress -InputObject @{ state = $State })
                $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Set traffic profile '$Name' to $State" })
            } catch {
                $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to set traffic profile '$Name' to $($State): $(Get-NormalizedError -Message $_.Exception.Message)" })
            }
        }
        if ($null -ne $RequiredWrite) {
            $Target = $RequiredWrite ? 'only its assigned users and groups' : 'all users'
            try {
                $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals/$SpId" -tenantid $TenantFilter -AsApp $true -type PATCH -body (ConvertTo-Json -Compress -InputObject @{ appRoleAssignmentRequired = $RequiredWrite })
                $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Applied traffic profile '$Name' to $Target" })
            } catch {
                $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to apply traffic profile '$Name' to $($Target): $(Get-NormalizedError -Message $_.Exception.Message)" })
            }
        }
        foreach ($Assignee in $AssignmentAdds) {
            $Label = "$($Assignee.type) '$($Assignee.label ?? $Assignee.value)'".Trim()
            try {
                $Body = ConvertTo-Json -Compress -InputObject ([ordered]@{ principalId = "$($Assignee.value)"; resourceId = $SpId; appRoleId = '00000000-0000-0000-0000-000000000000' })
                $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals/$SpId/appRoleAssignedTo" -tenantid $TenantFilter -AsApp $true -type POST -body $Body
                $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Assigned traffic profile '$Name' to $Label" })
            } catch {
                $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to assign traffic profile '$Name' to $($Label): $(Get-NormalizedError -Message $_.Exception.Message)" })
            }
        }
        foreach ($Assignment in $AssignmentRemoves) {
            $Label = "$($Assignment.principalType) '$($Assignment.principalDisplayName ?? $Assignment.principalId)'"
            try {
                $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals/$SpId/appRoleAssignedTo/$($Assignment.id)" -tenantid $TenantFilter -AsApp $true -type DELETE -body ''
                $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Removed $Label from traffic profile '$Name'" })
            } catch {
                $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to remove $Label from traffic profile '$Name': $(Get-NormalizedError -Message $_.Exception.Message)" })
            }
        }
        foreach ($Network in $NetworkWrites) {
            $Verb = $Network.add ? 'Added' : 'Removed'
            try {
                $Body = ConvertTo-Json -Depth 5 -Compress -InputObject ([ordered]@{
                        '@context' = '#$delta'
                        value      = @($Network.profileIds.ForEach({ [ordered]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfile'; id = $_ } }))
                    })
                $null = New-GraphPOSTRequest -uri "$Graph/networkAccess/connectivity/remoteNetworks/$($Network.id)/forwardingProfiles" -tenantid $TenantFilter -AsApp $true -type PATCH -body $Body
                $Results.Add([pscustomobject]@{ state = 'success'; resultText = "$Verb remote network '$($Network.name)' $($Network.add ? 'to' : 'from') traffic profile '$Name'" })
            } catch {
                $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to change the traffic profiles of remote network '$($Network.name)': $(Get-NormalizedError -Message $_.Exception.Message)" })
            }
        }
        # One write at a time: concurrent writes to one forwarding policy lose updates
        foreach ($RuleWrite in $RuleWrites) {
            try {
                foreach ($RuleId in $RuleWrite.ruleIds) {
                    $null = New-GraphPOSTRequest -uri "$Graph/networkAccess/forwardingPolicies/$($RuleWrite.policyId)/policyRules/$RuleId" -tenantid $TenantFilter -AsApp $true -type DELETE -body ''
                }
                foreach ($Rule in $RuleWrite.rules) {
                    $null = New-GraphPOSTRequest -uri "$Graph/networkAccess/forwardingPolicies/$($RuleWrite.policyId)/policyRules" -tenantid $TenantFilter -AsApp $true -type POST -body (ConvertTo-Json -Depth 10 -Compress -InputObject $Rule)
                }
                $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Updated the $($RuleWrite.policy) destinations of traffic profile '$Name'" })
            } catch {
                $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to replace the $($RuleWrite.policy) rules: $(Get-NormalizedError -Message $_.Exception.Message)" })
            }
        }

        if ($Results.Count -eq 0) { $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Traffic profile '$Name' already matches; nothing changed" }) }
        foreach ($Result in $Results) {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result.resultText -Sev ($Result.state -eq 'error' ? 'Error' : 'Info')
        }
        $StatusCode = Get-CippBulkStatusCode -Total $Results.Count -Failed @($Results.Where({ $_.state -eq 'error' })).Count
    } catch {
        $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to update traffic profile '$Name': $(Get-NormalizedError -Message $_.Exception.Message)" })
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to update traffic profile '$Name': $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = @($Results) } })
}
