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

        $SecurityGroups = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=securityEnabled eq true and mailEnabled eq false&`$count=true" -tenantid $TenantFilter
        $VacationGroup = $SecurityGroups | Where-Object { $_.displayName -contains "Vacation Exclusion - $($Policy.displayName)" }

        if (!$VacationGroup) {
            Write-Information "Creating vacation group: Vacation Exclusion - $($Policy.displayName)"
            $Guid = [guid]::NewGuid().ToString()
            $GroupObject = @{
                groupType       = 'generic'
                displayName     = "Vacation Exclusion - $($Policy.displayName)"
                username        = "vacation$Guid"
                securityEnabled = $true
            }
            $NewGroup = New-CIPPGroup -GroupObject $GroupObject -TenantFilter $TenantFilter -APIName 'Invoke-ExecCAExclusion'
            $GroupId = $NewGroup.GroupId
        } else {
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
                }
                Add-CIPPScheduledTask -Task $AuditRemoveTask -hidden $true
            }
            $body = @{ Results = "Successfully added vacation mode schedule for $Username." }
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
        $body = @{ Results = "Failed to perform exclusion for $Username : $($_.Exception.Message)" }
        Write-LogMessage -headers $Headers -API 'Invoke-ExecCAExclusion' -message "Failed to perform exclusion for $Username : $_" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
