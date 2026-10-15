function Invoke-CIPPStandardPlannerBlockTaskDelete {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PlannerBlockTaskDelete
    .SYNOPSIS
        (Label) Block Planner users from deleting tasks they did not create
    .DESCRIPTION
        (Helptext) Stops users from deleting Planner tasks that someone else created. Applies to all of a user's plans, and may also stop them from deleting plans. Use the group fields to limit who it applies to.
        (DocsDescription) Sets Planner's per-user policy that blocks deleting tasks created by someone else. The policy covers every plan the user can access (not a single board) and can also block deleting plans. Only enabled member accounts with a Planner license are changed; guests and disabled accounts are skipped. Use include groups to apply it to specific people only, and exclude groups to leave people out. If a named group can't be found, the run is skipped. Because each user is set one at a time, remediation runs at most once a day per tenant; alerts and reports check every run.
    .NOTES
        CAT
            Teams Standards
        TAG
        EXECUTIVETEXT
            Stops employees from deleting Planner tasks they did not create, reducing accidental loss on boards used as shared work queues. Can be limited to a department security group so only those staff are locked down.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.PlannerBlockTaskDelete.includeGroups","label":"Only apply to members of these groups (leave blank for all users)"}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.PlannerBlockTaskDelete.excludeGroups","label":"Skip members of these groups (display names)"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-09-16
        POWERSHELLEQUIVALENT
            Set-PlannerUserPolicy -UserAadIdOrPrincipalName user@domain.com -BlockDeleteTasksNotCreatedBySelf \$true
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "PROJECTWORKMANAGEMENT"
        UPDATECOMMENTBLOCK
            Run the tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'PlannerBlockTaskDelete' -TenantFilter $Tenant -RequiredCapabilities @('PROJECTWORKMANAGEMENT')
    if ($TestResult -eq $false) {
        return $true
    }

    $TasksScope = 'https://tasks.office.com/.default'
    # Microsoft Planner service plan (PROJECTWORKMANAGEMENT) - only users with this enabled need UserPolicy.
    $PlannerPlanId = 'b737dad2-2f6c-4c65-90e3-ca563267e8b9'

    $ToNames = {
        param($Value)
        @(@($Value) | ForEach-Object {
                if ($_ -is [string]) { $_ } else { "$($_.value ?? $_.label)" }
            } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    }
    $IncludeNames = & $ToNames $Settings.includeGroups
    $ExcludeNames = & $ToNames $Settings.excludeGroups

    try {
        $AllUsers = @(New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users' | Where-Object { $_ })
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get users for PlannerBlockTaskDelete in $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Group scoping: names resolve live by display name (a template applies to many tenants,
    # so an id would only ever match one) and expand to TRANSITIVE user members. An
    # unresolved name or a failed lookup aborts the run - sweeping with half a scope is wrong.
    $IncludedIds = @{}
    $ExcludedIds = @{}
    if ($IncludeNames.Count -gt 0 -or $ExcludeNames.Count -gt 0) {
        try {
            $MemberRequests = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($Scope in @(@{ Prefix = 'include'; Names = $IncludeNames }, @{ Prefix = 'exclude'; Names = $ExcludeNames })) {
                foreach ($Name in $Scope.Names) {
                    $EscapedName = $Name -replace "'", "''"
                    $GroupFilter = [System.Uri]::EscapeDataString("displayName eq '$EscapedName'")
                    $Groups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups?`$filter=$GroupFilter&`$select=id,displayName" -tenantid $Tenant | Where-Object { $_.id })
                    if ($Groups.Count -eq 0) { throw "the group '$Name' does not exist in this tenant" }
                    foreach ($Group in $Groups) {
                        $MemberRequests.Add(@{ id = "$($Scope.Prefix)-$($Group.id)"; method = 'GET'; url = "groups/$($Group.id)/transitiveMembers/microsoft.graph.user?`$select=id&`$top=999" })
                    }
                }
            }
            $Responses = @(New-GraphBulkRequest -tenantid $Tenant -Requests @($MemberRequests) -asapp $true -Version 'v1.0')
            foreach ($Response in $Responses) {
                if ([int]$Response.status -lt 200 -or [int]$Response.status -gt 299) {
                    throw "membership lookup for $($Response.id) returned $($Response.status) $($Response.body.error.message)"
                }
                $Bucket = if ("$($Response.id)".StartsWith('include-')) { $IncludedIds } else { $ExcludedIds }
                foreach ($MemberId in @($Response.body.value.id | Where-Object { $_ })) { $Bucket["$MemberId"] = $true }
            }
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "PlannerBlockTaskDelete: could not resolve the configured groups, refusing to run with a partial scope. Error: $ErrorMessage" -Sev Error
            return
        }
    }

    $Candidates = @($AllUsers | Where-Object {
            $_.userType -eq 'Member' -and $_.accountEnabled -eq $true -and $_.id -and $_.userPrincipalName -and
            ($_.assignedPlans | Where-Object { $_.capabilityStatus -eq 'Enabled' -and $_.servicePlanId -eq $PlannerPlanId })
        })
    if ($IncludeNames.Count -gt 0) { $Candidates = @($Candidates | Where-Object { $IncludedIds.ContainsKey("$($_.id)") }) }
    if ($ExcludeNames.Count -gt 0) { $Candidates = @($Candidates | Where-Object { -not $ExcludedIds.ContainsKey("$($_.id)") }) }

    # Remediate is idempotent PUT-all: no preflight GET (UserPolicy has no list/bulk API).
    # 24h guard (same pattern as SPGuestPeoplePicker) - alert/report below still run every time.
    if ($Settings.remediate -eq $true) {
        if ($Candidates.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'PlannerBlockTaskDelete: no in-scope Planner-licensed member users to update.' -sev Info
        } elseif (Test-CIPPRerun -Tenant $Tenant -API 'PlannerBlockTaskDelete' -Interval 86400 -Settings $Settings) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'PlannerBlockTaskDelete: write sweep already ran within the last 24h - skipping remediate until the guard expires or settings change.' -sev Info
        } else {
            $SuccessCount = 0
            $Failures = [System.Collections.Generic.List[object]]::new()
            foreach ($User in $Candidates) {
                $Upn = "$($User.userPrincipalName)"
                $SafeUpn = $Upn -replace "'", "''"
                $Uri = "https://tasks.office.com/taskAPI/tenantAdminSettings/UserPolicy('$SafeUpn')"
                $Body = @{ blockDeleteTasksNotCreatedBySelf = $true } | ConvertTo-Json -Compress
                try {
                    $null = New-GraphPOSTRequest -uri $Uri -tenantid $Tenant -scope $TasksScope -AsApp $true -type 'PUT' -body $Body
                    $SuccessCount++
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $Failures.Add([pscustomobject]@{
                            userPrincipalName = $Upn
                            error             = $ErrorMessage.NormalizedError
                        })
                }
            }
            if ($Failures.Count -eq 0) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "PlannerBlockTaskDelete: successfully updated $SuccessCount users." -sev Info
            } else {
                $ReasonSummary = (
                    $Failures | Group-Object -Property error | ForEach-Object {
                        "$($_.Count) user(s): $($_.Name)"
                    }
                ) -join '; '
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "PlannerBlockTaskDelete: updated $SuccessCount of $($Candidates.Count) users; one or more failed due to: $ReasonSummary" -sev Error -LogData @($Failures)
            }
        }
    }

    # Alert/report need live state; GET only when those modes are on.
    $IncorrectUsers = [System.Collections.Generic.List[object]]::new()
    if ($Settings.alert -eq $true -or $Settings.report -eq $true) {
        foreach ($User in $Candidates) {
            $Upn = "$($User.userPrincipalName)"
            $SafeUpn = $Upn -replace "'", "''"
            $Uri = "https://tasks.office.com/taskAPI/tenantAdminSettings/UserPolicy('$SafeUpn')"
            try {
                $Policy = New-GraphGetRequest -uri $Uri -tenantid $Tenant -scope $TasksScope -AsApp $true
                $Blocked = [bool]($Policy.blockDeleteTasksNotCreatedBySelf -eq $true)
                if (-not $Blocked) {
                    $IncorrectUsers.Add([pscustomobject]@{
                            id                               = $User.id
                            userPrincipalName                = $Upn
                            displayName                      = $User.displayName
                            blockDeleteTasksNotCreatedBySelf = $Policy.blockDeleteTasksNotCreatedBySelf
                        })
                }
            } catch {
                $Message = "$($_.Exception.Message)"
                # First GET can 403 until a policy exists for the tenant/user; treat as non-compliant.
                if ($Message -match '403|404|Access is denied|Not Found|Forbidden') {
                    $IncorrectUsers.Add([pscustomobject]@{
                            id                               = $User.id
                            userPrincipalName                = $Upn
                            displayName                      = $User.displayName
                            blockDeleteTasksNotCreatedBySelf = $null
                        })
                } else {
                    $ErrorMessage = Get-NormalizedError -Message $Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "PlannerBlockTaskDelete: failed to read UserPolicy for $Upn. Error: $ErrorMessage" -Sev Error
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($IncorrectUsers.Count -gt 0) {
            Write-StandardsAlert -message 'The following accounts are not blocked from deleting Planner tasks they did not create' -object @($IncorrectUsers) -tenant $Tenant -standardName 'PlannerBlockTaskDelete' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "PlannerBlockTaskDelete: $($IncorrectUsers.Count) in-scope account(s) are missing blockDeleteTasksNotCreatedBySelf." -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All in-scope accounts have Planner blockDeleteTasksNotCreatedBySelf enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $FieldValue = @($IncorrectUsers | Select-Object -Property userPrincipalName, displayName, blockDeleteTasksNotCreatedBySelf)

        $CurrentValue = @{
            incorrectUsers = @($FieldValue)
        }
        $ExpectedValue = @{
            incorrectUsers = @()
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.PlannerBlockTaskDelete' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
