function Convert-CIPPCAGroupNameToId {
    <#
    .SYNOPSIS
        Replaces group display names in a CA policy assignment with group object IDs, creating missing groups with -CreateGroups.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        $GroupNames,
        $Groups,
        $CreateGroups = $false,
        $GroupTemplates,
        $NotFoundHint = "Enable 'Create groups if they do not exist' or create the group manually before deploying this policy.",
        $Headers,
        $APIName = 'Create CA Policy'
    )

    $GroupIds = [System.Collections.Generic.List[string]]::new()
    $GroupNames | ForEach-Object {
        if (Test-IsGuid -String $_) {
            Write-LogMessage -Headers $Headers -API $APIName -message "Already GUID, no need to replace: $_" -Sev 'Debug'
            $GroupIds.Add($_) # it's a GUID, so we keep it
        } else {
            $matchedGroups = @($Groups | Where-Object -Property displayName -EQ $_)
            $groupId = $matchedGroups.id # it's a display name, so we get the group ID
            if ($groupId) {
                if ($matchedGroups.Count -gt 1) {
                    Write-Warning "Multiple groups found with display name '$_'. Using the first match: $($matchedGroups[0].id). IDs found: $($groupId -join ', ')"
                    $null = Write-LogMessage -Headers $Headers -API $APIName -message "Multiple groups found with display name '$_'. Using first match: $($matchedGroups[0].id)" -Sev 'Warning'
                    $groupId = @($matchedGroups[0].id)
                }
                foreach ($gid in $groupId) {
                    Write-Warning "Replaced group name $_ with ID $gid"
                    $null = Write-LogMessage -Headers $Headers -API $APIName -message "Replaced group name $_ with ID $gid" -Sev 'Debug'
                    $GroupIds.Add($gid) # add the ID to the list
                }
            } elseif ($CreateGroups) {
                Write-Warning "Creating group $_ as it does not exist in the tenant"
                # A template store with duplicate display names returns every match here. Passing that
                # array to New-CIPPGroup makes the Graph create body's displayName an array, so the
                # create fails ("Unexpected token: StartArray. Path 'resourcePayload.displayName'") and
                # leaves an empty group id, which Graph then rejects with the opaque
                # "1054: Invalid group value: ." on the whole policy. Select a single template.
                $MatchingTemplates = @($GroupTemplates | Where-Object -Property displayName -EQ $_)
                if ($MatchingTemplates.Count -gt 0) {
                    if ($MatchingTemplates.Count -gt 1) {
                        Write-Warning "Multiple group templates found with display name '$_'. Using the first match."
                        $null = Write-LogMessage -Headers $Headers -API $APIName -message "Multiple group templates found with display name '$_'. Using the first match; remove the duplicate group template." -Sev 'Warning'
                    }
                    Write-Information "Creating group from template for $_"
                    $NewGroup = New-CIPPGroup -GroupObject ($MatchingTemplates | Select-Object -First 1) -TenantFilter $TenantFilter -APIName $APIName
                } else {
                    Write-Information "No template found, creating security group for $_"
                    $username = $_ -replace '[^a-zA-Z0-9]', ''
                    if ($username.Length -gt 64) {
                        $username = $username.Substring(0, 64)
                    }
                    $GroupObject = @{
                        groupType       = 'generic'
                        displayName     = $_
                        username        = $username
                        securityEnabled = $true
                    }
                    $NewGroup = New-CIPPGroup -GroupObject $GroupObject -TenantFilter $TenantFilter -APIName $APIName
                }
                # Fail closed: never add an empty id. A dropped exclusion silently widens the policy
                # (e.g. break-glass accounts no longer excluded), and Graph rejects the empty value
                # anyway. Surface why the create failed instead of the opaque 1054 group error.
                if (-not $NewGroup.Success -or [string]::IsNullOrWhiteSpace($NewGroup.GroupId)) {
                    throw "Failed to create group '$_' in tenant $TenantFilter$(if ($NewGroup.Error) { ": $($NewGroup.Error)" }). Resolve the group manually or remove the duplicate group template, then redeploy."
                }
                $GroupIds.Add($NewGroup.GroupId)
            } else {
                Write-Warning "Group $_ not found in the tenant and CreateGroups is disabled"
                throw [System.Management.Automation.ItemNotFoundException]::new("Group '$_' not found in tenant $TenantFilter. $NotFoundHint")
            }
        }
    }
    return $GroupIds
}
