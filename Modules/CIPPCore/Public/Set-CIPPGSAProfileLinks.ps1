function Set-CIPPGSAProfileLinks {
    <#
    .SYNOPSIS
        Brings a Global Secure Access security profile's policy links in line with the wanted set.
    .DESCRIPTION
        Links are the wanted links (policyId, policyName, priority, state, loggingState); Current are
        the profile's links from Graph (policies expanded with policy). Unwanted links are deleted.
        A link whose logging differs is deleted and created again, because Graph refuses to patch
        loggingState. Priority and state changes are patched; link priorities are unique within a
        profile, so when a target priority is still held by another link, the moving links first go
        to free temporary priorities. Missing links are created last. Returns one result per write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string]$ProfileId,
        [string]$ProfileName,
        [object[]]$Links = @(),
        [object[]]$Current = @()
    )

    $Links = @($Links).Where({ $null -ne $_ })
    $Current = @($Current).Where({ $null -ne $_ })
    $Uri = "https://graph.microsoft.com/beta/networkAccess/filteringProfiles/$ProfileId/policies"
    $Results = [System.Collections.Generic.List[object]]::new()
    $Wanted = @{}
    foreach ($Link in $Links) { $Wanted[[string]$Link.policyId] = $Link }
    $Kept = [ordered]@{}

    foreach ($Link in @($Current)) {
        $Desired = $Wanted[[string]$Link.policy.id]
        $Name = "$ProfileName -> $($Link.policy.name)"
        if ($Desired -and $Link.loggingState -eq $Desired.loggingState) { $Kept[[string]$Link.policy.id] = $Link; continue }
        try {
            $null = New-GraphPOSTRequest -uri "$Uri/$($Link.id)" -tenantid $TenantFilter -AsApp $true -type DELETE -body ''
            if (-not $Desired) { $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Unlinked '$Name'" }) }
        } catch {
            $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to unlink '$Name': $(Get-NormalizedError -Message $_.Exception.Message)" })
            if ($Desired) { $Kept[[string]$Link.policy.id] = $Link }
        }
    }

    $Moves = @($Kept.Values.Where({ [int64]$_.priority -ne [int64]$Wanted[[string]$_.policy.id].priority -or $_.state -ne $Wanted[[string]$_.policy.id].state }))
    $Held = [System.Collections.Generic.HashSet[int64]]::new()
    foreach ($Link in $Kept.Values) { $null = $Held.Add([int64]$Link.priority) }
    $Taken = $Moves.Where({ $Target = [int64]$Wanted[[string]$_.policy.id].priority; $Target -ne [int64]$_.priority -and $Held.Contains($Target) })
    if ($Taken.Count) {
        $Reserved = [System.Collections.Generic.HashSet[int64]]::new($Held)
        foreach ($Link in $Links) { $null = $Reserved.Add([int64]$Link.priority) }
        $Free = 65000
        foreach ($Link in $Moves.Where({ [int64]$_.priority -ne [int64]$Wanted[[string]$_.policy.id].priority })) {
            while ($Reserved.Contains($Free)) { $Free-- }
            try {
                $null = New-GraphPOSTRequest -uri "$Uri/$($Link.id)" -tenantid $TenantFilter -AsApp $true -type PATCH -body (ConvertTo-Json -Compress -InputObject @{ '@odata.type' = '#microsoft.graph.networkaccess.filteringPolicyLink'; priority = $Free })
                $null = $Reserved.Add($Free)
            } catch {
                $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to reorder link '$ProfileName -> $($Link.policy.name)': $(Get-NormalizedError -Message $_.Exception.Message)" })
            }
        }
    }
    foreach ($Link in $Moves) {
        $Desired = $Wanted[[string]$Link.policy.id]
        try {
            $Body = ConvertTo-Json -Compress -InputObject ([ordered]@{ '@odata.type' = '#microsoft.graph.networkaccess.filteringPolicyLink'; priority = [int64]$Desired.priority; state = $Desired.state })
            $null = New-GraphPOSTRequest -uri "$Uri/$($Link.id)" -tenantid $TenantFilter -AsApp $true -type PATCH -body $Body
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Updated link '$ProfileName -> $($Desired.policyName)' (priority $($Desired.priority), $($Desired.state))" })
        } catch {
            $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to update link '$ProfileName -> $($Desired.policyName)': $(Get-NormalizedError -Message $_.Exception.Message)" })
        }
    }

    foreach ($Desired in @($Links).Where({ -not $Kept.Contains([string]$_.policyId) })) {
        $Recreated = @($Current).Where({ $_.policy.id -eq $Desired.policyId }).Count -gt 0
        try {
            $Body = ConvertTo-Json -Depth 5 -Compress -InputObject ([ordered]@{
                    '@odata.type' = '#microsoft.graph.networkaccess.filteringPolicyLink'
                    priority      = [int64]$Desired.priority
                    state         = $Desired.state
                    loggingState  = $Desired.loggingState
                    policy        = [ordered]@{ id = $Desired.policyId; '@odata.type' = '#microsoft.graph.networkaccess.filteringPolicy' }
                })
            $null = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -AsApp $true -type POST -body $Body
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = if ($Recreated) { "Recreated link '$ProfileName -> $($Desired.policyName)' to $($Desired.loggingState -replace 'd$', '') logging" } else { "Linked '$($Desired.policyName)' to security profile '$ProfileName'" } })
        } catch {
            $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to link '$($Desired.policyName)' to security profile '$ProfileName': $(Get-NormalizedError -Message $_.Exception.Message)" })
        }
    }

    @($Results)
}
