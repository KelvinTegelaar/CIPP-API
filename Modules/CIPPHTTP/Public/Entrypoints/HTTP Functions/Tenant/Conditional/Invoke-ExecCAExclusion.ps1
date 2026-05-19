function Invoke-ExecCAExclusion {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers

    try {
        #If UserId is a guid, get the user's UPN
        $TenantFilter = $Request.Body.tenantFilter
        $UserID = $Request.Body.UserID
        $Username = $Request.Body.Username
        $Users = $Request.Body.Users
        $EndDate = $Request.Body.EndDate
        $PolicyId = $Request.Body.PolicyId
        $ExclusionType = $Request.Body.ExclusionType
        $ExcludeLocationAuditAlerts = $Request.Body.excludeLocationAuditAlerts

        if ($Users) {
            $UserID = $Users.value
            $Username = $Users.addedFields.userPrincipalName -join ', '
        } else {
            if ($UserID -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$' -and -not $Username) {
                $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)" -tenantid $TenantFilter).userPrincipalName
            }
        }

        $Policy = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)?`$select=id,displayName,conditions" -tenantid $TenantFilter -asApp $true

        if (-not $Policy) {
            throw "Policy with ID $PolicyId not found in tenant $TenantFilter."
        }

        $VacationGroupName = "Vacation Exclusion - $($Policy.displayName)"
        $escapedGroupName = $VacationGroupName -replace "'", "''"
        $groupFilter = "displayName eq '$escapedGroupName' and mailEnabled eq false and securityEnabled eq true"
        $encodedGroupFilter = [System.Uri]::EscapeDataString($groupFilter)
        $VacationGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$encodedGroupFilter" -tenantid $TenantFilter)

        $DuplicateGroupWarning = $null
        if ($VacationGroups.Count -eq 0) {
            Write-Information "Creating vacation group: $VacationGroupName"
            $Guid = [guid]::NewGuid().ToString()
            $GroupObject = @{
                groupType       = 'generic'
                displayName     = $VacationGroupName
                username        = "vacation$Guid"
                securityEnabled = $true
            }
            $NewGroup = New-CIPPGroup -GroupObject $GroupObject -TenantFilter $TenantFilter -APIName 'Invoke-ExecCAExclusion'
            $GroupId = $NewGroup.GroupId
        } else {
            $VacationGroup = $VacationGroups | Select-Object -First 1
            if ($VacationGroups.Count -gt 1) {
                $DuplicateGroupWarning = "Failed to find a unique vacation group for policy '$($Policy.displayName)'. Multiple groups found, using group $($VacationGroup.id)."
                Write-Warning "Multiple vacation groups found for policy '$($Policy.displayName)'. Using group $($VacationGroup.id)."
            }
            Write-Information "Using existing vacation group: $($VacationGroup.displayName)"
            $GroupId = $VacationGroup.id
        }

        if ($Policy.conditions.users.excludeGroups -notcontains $GroupId) {
            Set-CIPPCAExclusion -TenantFilter $TenantFilter -ExclusionType 'Add' -PolicyId $PolicyId -Groups @{ value = @($GroupId); addedFields = @{ displayName = @("Vacation Exclusion - $($Policy.displayName)") } } -Headers $Headers
        }

        $PolicyName = $Policy.displayName
        if ($Request.Body.vacation -eq 'true') {
            $StartDate = $Request.Body.StartDate
            $EndDate = $Request.Body.EndDate
            # Detect if policy targets specific named locations (GUIDs) and user requested audit log exclusion
            $GuidRegex = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            $LocationIds = @()
            if ($Policy.conditions.locations.includeLocations) { $LocationIds += $Policy.conditions.locations.includeLocations }
            if ($Policy.conditions.locations.excludeLocations) { $LocationIds += $Policy.conditions.locations.excludeLocations }
            $PolicyHasGuidLocations = $LocationIds | Where-Object { $_ -match $GuidRegex }

            $Parameters = [PSCustomObject]@{
                GroupType = 'Security'
                GroupId   = $GroupId
                Member    = $Users.addedFields.userPrincipalName ?? $Users.value ?? $Users ?? $UserID
            }

            $TaskBody = [pscustomobject]@{
                TenantFilter  = $TenantFilter
                Name          = "Add CA Exclusion Vacation Mode: $PolicyName"
                Command       = @{
                    value = 'Add-CIPPGroupMember'
                    label = 'Add-CIPPGroupMember'
                }
                Parameters    = [pscustomobject]$Parameters
                ScheduledTime = $StartDate
                PostExecution = $Request.Body.postExecution
                Reference     = $Request.Body.reference
            }

            Write-Information ($TaskBody | ConvertTo-Json -Depth 10)

            Add-CIPPScheduledTask -Task $TaskBody -hidden $false
            # Optional: schedule audit log exclusion add task if requested and policy has location GUIDs
            if ($ExcludeLocationAuditAlerts -and $PolicyHasGuidLocations) {
                $AuditUsers = $Users.addedFields.userPrincipalName ?? $Users.value ?? $Users ?? $UserID
                $AuditAddTask = [pscustomobject]@{
                    TenantFilter  = $TenantFilter
                    Name          = "Add Audit Log Location Exclusion: $PolicyName"
                    Command       = @{ value = 'Set-CIPPAuditLogUserExclusion'; label = 'Set-CIPPAuditLogUserExclusion' }
                    Parameters    = [pscustomobject]@{ Users = $AuditUsers; Action = 'Add'; Type = 'Location' }
                    ScheduledTime = $StartDate
                }
                Add-CIPPScheduledTask -Task $AuditAddTask -hidden $true
            }
            #Removal of the exclusion
            $TaskBody.Command = @{
                label = 'Remove-CIPPGroupMember'
                value = 'Remove-CIPPGroupMember'
            }
            $TaskBody.Name = "Remove CA Exclusion Vacation Mode: $PolicyName"
            $TaskBody.ScheduledTime = $EndDate
            Add-CIPPScheduledTask -Task $TaskBody -hidden $false
            if ($ExcludeLocationAuditAlerts -and $PolicyHasGuidLocations) {
                $AuditUsers = $Users.addedFields.userPrincipalName ?? $Users.value ?? $Users ?? $UserID
                $AuditRemoveTask = [pscustomobject]@{
                    TenantFilter  = $TenantFilter
                    Name          = "Remove Audit Log Location Exclusion: $PolicyName"
                    Command       = @{ value = 'Set-CIPPAuditLogUserExclusion'; label = 'Set-CIPPAuditLogUserExclusion' }
                    Parameters    = [pscustomobject]@{ Users = $AuditUsers; Action = 'Remove'; Type = 'Location' }
                    ScheduledTime = $EndDate
                    Reference     = $Request.Body.reference
                }
                Add-CIPPScheduledTask -Task $AuditRemoveTask -hidden $true
            }
            $Results = @("Successfully added vacation mode schedule for $Username on policy '$PolicyName'.")
            if ($DuplicateGroupWarning) {
                $Results += $DuplicateGroupWarning
            }
            $body = @{ Results = $Results }
        } else {
            $Parameters = @{
                ExclusionType = $ExclusionType
                PolicyId      = $PolicyId
            }
            if ($Users) {
                $Parameters.Users = $Users
            } else {
                $Parameters.UserID = $UserID
            }

            Set-CIPPCAExclusion -TenantFilter $TenantFilter -Headers $Headers @Parameters
        }
    } catch {
        Write-Warning "Failed to perform exclusion for $Username : $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        $PolicyLabel = if ($PolicyName) { " on policy '$PolicyName'" } else { '' }
        $Results = @("Failed to perform exclusion for $Username${PolicyLabel}: $($_.Exception.Message)")
        if ($DuplicateGroupWarning) {
            $Results += $DuplicateGroupWarning
        }
        $body = @{ Results = $Results }
        Write-LogMessage -headers $Headers -API 'Invoke-ExecCAExclusion' -message "Failed to perform exclusion for $Username : $_" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
