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
            Graph API PATCH https://graph.microsoft.com/beta/policies/b2bManagementPolicies/default
        RECOMMENDEDBY
            "CIS"
        REQUIREDCAPABILITIES
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $Uri = 'https://graph.microsoft.com/beta/policies/b2bManagementPolicies/default'

    try {
        $CurrentState = New-GraphGetRequest -Uri $Uri -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get B2B management policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $CurrentDomains = $CurrentState.invitationsAllowedAndBlockedDomainsPolicy
    $HasRestrictions = $CurrentDomains -and (
        ($CurrentDomains.allowedDomains -and $CurrentDomains.allowedDomains.Count -gt 0) -or
        ($CurrentDomains.blockedDomains -and $CurrentDomains.blockedDomains.Count -gt 0)
    )

    $DesiredDomains = @()
    if ($Settings.allowedDomains) {
        $DesiredDomains = @($Settings.allowedDomains -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    if ($DesiredDomains.Count -gt 0) {
        $CurrentAllowed = @($CurrentDomains.allowedDomains | Sort-Object)
        $DesiredSorted = @($DesiredDomains | Sort-Object)
        $StateIsCorrect = ($null -ne $CurrentDomains) -and ($CurrentAllowed -join ',') -eq ($DesiredSorted -join ',')
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
                $Body = @{
                    invitationsAllowedAndBlockedDomainsPolicy = @{
                        allowedDomains = $DesiredDomains
                    }
                } | ConvertTo-Json -Depth 10 -Compress

                $null = New-GraphPostRequest -Uri $Uri -Body $Body -TenantID $Tenant -Type PATCH -ContentType 'application/json'
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
