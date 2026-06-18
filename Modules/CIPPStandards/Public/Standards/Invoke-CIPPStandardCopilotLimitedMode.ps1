function Invoke-CIPPStandardCopilotLimitedMode {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) CopilotLimitedMode
    .SYNOPSIS
        (Label) Configure Microsoft 365 Copilot Limited Mode (Teams meetings)
    .DESCRIPTION
        (Helptext) Controls Microsoft 365 Copilot Limited Mode for Teams meetings. When enabled for a group, Copilot in Teams meetings does not respond to sentiment-related prompts (inferring emotions, behavior, or judgments) for members of the selected group. A target group is required when enabling. Managed via the Copilot admin settings Graph API.
        (DocsDescription) Configures the `copilotAdminLimitedMode` setting through the `/copilot/admin/settings/limitedMode` Microsoft Graph API (beta). When enabled, `isEnabledForGroup` is set to true and applied to the resolved target group; when disabled, `isEnabledForGroup` is set to false. NOTE: this API currently requires delegated authentication and the acting identity must be Global Administrator to write the setting.
    .NOTES
        CAT
            Copilot (M365) Standards
        TAG
        EXECUTIVETEXT
            Limits Microsoft 365 Copilot in Teams meetings so it does not provide opinions on sentiment, emotions, or judgments for a selected group of users. This helps organizations meet workplace policy, privacy, and works-council requirements while still allowing Copilot to summarize and answer factual questions grounded in the meeting.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.CopilotLimitedMode.LimitedModeEnabled","label":"Enable Copilot Limited Mode for a group (Teams meetings)","defaultValue":false}
            {"type":"textField","name":"standards.CopilotLimitedMode.GroupName","label":"Target Group Name (wildcard match; required when enabled)","required":false,"condition":{"field":"standards.CopilotLimitedMode.LimitedModeEnabled","compareType":"is","compareValue":true}}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-06-09
        POWERSHELLEQUIVALENT
            Graph API: PATCH /beta/copilot/admin/settings/limitedMode
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $LimitedModeUri = 'https://graph.microsoft.com/beta/copilot/admin/settings/limitedMode'
    $DesiredEnabled = [bool]$Settings.LimitedModeEnabled
    $GroupName = $Settings.GroupName

    # Read current state. The Copilot admin settings API currently requires delegated auth, so this
    # uses CIPP's default delegated token (no -AsApp).
    try {
        $CurrentState = New-GraphGetRequest -Uri $LimitedModeUri -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotLimitedMode: Could not retrieve the limited mode state. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    # When enabling, resolve the target group name (wildcard, first match) to a single group ID.
    $ResolvedGroupId = $null
    $GroupResolutionFailed = $false
    if ($DesiredEnabled) {
        if ([string]::IsNullOrWhiteSpace($GroupName)) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'CopilotLimitedMode: A target group name is required when enabling limited mode.' -sev Error
            $GroupResolutionFailed = $true
        } else {
            try {
                $EscapedName = $GroupName -replace "'", "''"
                $GroupFilter = [System.Uri]::EscapeDataString("startsWith(displayName,'$EscapedName')")
                $MatchedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$GroupFilter" -tenantid $Tenant)
                if ($MatchedGroups.Count -eq 0) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotLimitedMode: No group found matching '$GroupName'." -sev Warning
                    $GroupResolutionFailed = $true
                } else {
                    $ResolvedGroupId = $MatchedGroups[0].id
                    if ($MatchedGroups.Count -gt 1) {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotLimitedMode: Multiple groups matched '$GroupName', using '$($MatchedGroups[0].displayName)'." -sev Info
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotLimitedMode: Failed to resolve group '$GroupName'. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $GroupResolutionFailed = $true
            }
        }
    }

    # Determine compliance
    if ($DesiredEnabled) {
        $StateIsCorrect = (-not $GroupResolutionFailed) -and ($CurrentState.isEnabledForGroup -eq $true) -and ($CurrentState.groupId -eq $ResolvedGroupId)
    } else {
        $StateIsCorrect = ($CurrentState.isEnabledForGroup -eq $false)
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'CopilotLimitedMode: Already in the desired state.' -sev Info
        } elseif ($DesiredEnabled -and $GroupResolutionFailed) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'CopilotLimitedMode: Skipping remediation because the target group could not be resolved.' -sev Warning
        } else {
            try {
                $BodyObject = [ordered]@{
                    '@odata.type'     = '#microsoft.graph.copilotAdminLimitedMode'
                    isEnabledForGroup = $DesiredEnabled
                    groupId           = if ($DesiredEnabled) { $ResolvedGroupId } else { $null }
                }
                $Body = $BodyObject | ConvertTo-Json -Compress
                $null = New-GraphPostRequest -uri $LimitedModeUri -tenantid $Tenant -type PATCH -body $Body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotLimitedMode: Set limited mode to '$DesiredEnabled'$(if ($DesiredEnabled) { " for group '$GroupName'" })." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotLimitedMode: Failed to set limited mode. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'CopilotLimitedMode: Limited mode is in the desired state.' -sev Info
        } else {
            $AlertObject = [PSCustomObject]@{
                CurrentEnabled = $CurrentState.isEnabledForGroup
                CurrentGroupId = $CurrentState.groupId
                DesiredEnabled = $DesiredEnabled
            }
            Write-StandardsAlert -message 'CopilotLimitedMode: Limited mode is not in the desired state.' -object $AlertObject -tenant $Tenant -standardName 'CopilotLimitedMode' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'CopilotLimitedMode: Limited mode is not in the desired state.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            isEnabledForGroup = $CurrentState.isEnabledForGroup
            groupId           = $CurrentState.groupId
        }
        $ExpectedValue = @{
            isEnabledForGroup = $DesiredEnabled
            groupId           = if ($DesiredEnabled) { $ResolvedGroupId } else { $null }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.CopilotLimitedMode' -CurrentValue ([PSCustomObject]$CurrentValue) -ExpectedValue ([PSCustomObject]$ExpectedValue) -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'CopilotLimitedMode' -FieldValue ([bool]$StateIsCorrect) -StoreAs bool -Tenant $Tenant
    }
}
