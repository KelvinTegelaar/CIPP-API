function Invoke-CIPPStandardCollaborationDomainRestriction {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) CollaborationDomainRestriction
    .SYNOPSIS
        (Label) Restrict collaboration invitations to allowed domains only
    .DESCRIPTION
        (Helptext) Restricts B2B collaboration invitations to a specified list of allowed domains. If no domains are provided, the standard will alert and report on whether any domain restrictions are currently configured.
        (DocsDescription) By default, Microsoft Entra ID allows collaboration invitations to be sent to any external domain. CIS recommends restricting B2B collaboration invitations to only approved domains to reduce the risk of data exfiltration and unauthorized access. This standard checks the B2B management policy for an allow list of domains and can remediate by setting the allowed domains list.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS M365 6.0.1 (5.1.6.1)"
        EXECUTIVETEXT
            Restricts external collaboration invitations to approved domains only, preventing users from sharing data with unapproved external organizations. This reduces the risk of data exfiltration and ensures that collaboration occurs only with trusted business partners.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.CollaborationDomainRestriction.allowedDomains","label":"Allowed domains (comma separated)","required":false,"placeholder":"contoso.com, fabrikam.com"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-05-06
        POWERSHELLEQUIVALENT
            Graph API PATCH https://graph.microsoft.com/beta/policies/b2bManagementPolicies/{id}
        RECOMMENDEDBY
            "CIS"
        REQUIREDCAPABILITIES
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    # b2bManagementPolicies is a collection keyed by GUID - there is no 'default' singleton.
    # The policy inherits from stsPolicy, so the actual settings live in definition[0] as a JSON string:
    # {"B2BManagementPolicy":{"InvitationsAllowedAndBlockedDomainsPolicy":{"AllowedDomains":[],"BlockedDomains":[]},"AutoRedeemPolicy":{...}}}
    $Uri = 'https://graph.microsoft.com/beta/policies/b2bManagementPolicies'

    try {
        $Policies = @(New-GraphGetRequest -Uri $Uri -tenantid $Tenant)
        $CurrentState = $Policies | Where-Object { $_.isOrganizationDefault -eq $true } | Select-Object -First 1
        if (-not $CurrentState) { $CurrentState = $Policies | Select-Object -First 1 }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get B2B management policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    # Parse the definition blob. Keep the whole object around so remediation can preserve sibling
    # settings such as AutoRedeemPolicy instead of overwriting the entire definition.
    $Definition = $null
    if ($CurrentState.definition) {
        try {
            $Definition = @($CurrentState.definition)[0] | ConvertFrom-Json
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not parse the B2B management policy definition. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            return
        }
    }

    $DomainPolicy = $Definition.B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy
    $CurrentDomains = [PSCustomObject]@{
        allowedDomains = @($DomainPolicy.AllowedDomains)
        blockedDomains = @($DomainPolicy.BlockedDomains)
    }
    $HasRestrictions = ($CurrentDomains.allowedDomains.Count -gt 0) -or ($CurrentDomains.blockedDomains.Count -gt 0)

    $DesiredDomains = @()
    if ($Settings.allowedDomains) {
        $DesiredDomains = @($Settings.allowedDomains -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    if ($DesiredDomains.Count -gt 0) {
        $CurrentAllowed = @($CurrentDomains.allowedDomains | Sort-Object)
        $DesiredSorted = @($DesiredDomains | Sort-Object)
        $StateIsCorrect = ($CurrentAllowed -join ',') -eq ($DesiredSorted -join ',')
    } else {
        $StateIsCorrect = $HasRestrictions
    }

    if ($Settings.remediate -eq $true) {
        if ($DesiredDomains.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No allowed domains specified for CollaborationDomainRestriction. Skipping remediation.' -sev Info
        } elseif ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'B2B collaboration domain restrictions are already configured correctly.' -sev Info
        } else {
            try {
                # Rebuild the definition on top of the existing one so AutoRedeemPolicy and any other
                # settings inside the blob survive. AllowedDomains and BlockedDomains are mutually
                # exclusive in the portal, so setting an allow list clears the block list.
                if ($null -eq $Definition) { $Definition = [PSCustomObject]@{} }
                if ($null -eq $Definition.B2BManagementPolicy) {
                    $Definition | Add-Member -NotePropertyName 'B2BManagementPolicy' -NotePropertyValue ([PSCustomObject]@{}) -Force
                }
                $Definition.B2BManagementPolicy | Add-Member -NotePropertyName 'InvitationsAllowedAndBlockedDomainsPolicy' -NotePropertyValue ([PSCustomObject]@{
                        AllowedDomains = @($DesiredDomains)
                        BlockedDomains = @()
                    }) -Force

                $Body = @{
                    displayName           = 'B2BManagementPolicy'
                    definition            = @(($Definition | ConvertTo-Json -Depth 10 -Compress))
                    isOrganizationDefault = $true
                } | ConvertTo-Json -Depth 10 -Compress

                if ($CurrentState.id) {
                    $null = New-GraphPostRequest -Uri "$Uri/$($CurrentState.id)" -Body $Body -TenantID $Tenant -Type PATCH -ContentType 'application/json'
                } else {
                    $null = New-GraphPostRequest -Uri $Uri -Body $Body -TenantID $Tenant -Type POST -ContentType 'application/json'
                }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set B2B collaboration allowed domains to: $($DesiredDomains -join ', ')" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set B2B collaboration domain restrictions. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'B2B collaboration domain restrictions are configured.' -sev Info
        } else {
            $AlertMsg = if ($DesiredDomains.Count -gt 0) {
                "B2B collaboration allowed domains do not match expected list: $($DesiredDomains -join ', ')"
            } else {
                'B2B collaboration invitations are not restricted by domain allow/block list'
            }
            Write-StandardsAlert -message $AlertMsg -object $CurrentDomains -tenant $Tenant -standardName 'CollaborationDomainRestriction' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            hasRestrictions = $HasRestrictions
            allowedDomains  = $CurrentDomains.allowedDomains -join ', '
            blockedDomains  = $CurrentDomains.blockedDomains -join ', '
        }
        $ExpectedValue = @{
            hasRestrictions = $true
        }
        if ($DesiredDomains.Count -gt 0) {
            $ExpectedValue.allowedDomains = $DesiredDomains -join ', '
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.CollaborationDomainRestriction' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'CollaborationDomainRestriction' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
