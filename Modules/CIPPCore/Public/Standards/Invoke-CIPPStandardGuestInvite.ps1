function Invoke-CIPPStandardGuestInvite {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) GuestInvite
    .SYNOPSIS
        (Label) Guest Invite setting
    .DESCRIPTION
        (Helptext) This setting controls who can invite guests to your directory to collaborate on resources secured by your company, such as SharePoint sites or Azure resources.
        (DocsDescription) This setting controls who can invite guests to your directory to collaborate on resources secured by your company, such as SharePoint sites or Azure resources.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CISA (MS.AAD.18.1v1)"
            "EIDSCA.AP04"
            "EIDSCA.AP07"
        EXECUTIVETEXT
            Controls who within the organization can invite external partners and vendors to access company resources, ensuring proper oversight of external access while enabling necessary business collaboration. This helps maintain security while supporting partnership and vendor relationships.
        ADDEDCOMPONENT
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Who can send invites?","name":"standards.GuestInvite.allowInvitesFrom","options":[{"label":"Everyone","value":"everyone"},{"label":"Admins, Guest inviters and All Members","value":"adminsGuestInvitersAndAllMembers"},{"label":"Admins and Guest inviters","value":"adminsAndGuestInviters"},{"label":"None","value":"none"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-11-12
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the GuestInvite state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Input validation and value handling
    $AllowInvitesFromValue = $Settings.allowInvitesFrom.value ?? $Settings.allowInvitesFrom
    if (([string]::IsNullOrWhiteSpace($AllowInvitesFromValue) -or $AllowInvitesFromValue -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'GuestInvite: Invalid allowInvitesFrom parameter set' -sev Error
        return
    }

    $StateIsCorrect = ($CurrentState.allowInvitesFrom -eq $AllowInvitesFromValue)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Guest Invite settings is already applied correctly.' -Sev Info
        } else {
            try {
                $GraphRequest = @{
                    tenantID    = $Tenant
                    uri         = 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy'
                    AsApp       = $false
                    Type        = 'PATCH'
                    ContentType = 'application/json; charset=utf-8'
                    Body        = [pscustomobject]@{
                        allowInvitesFrom = $AllowInvitesFromValue
                    } | ConvertTo-Json -Compress
                }
                New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Successfully updated Guest Invite setting to $AllowInvitesFromValue" -Sev Info
            } catch {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to update Guest Invite setting to $AllowInvitesFromValue" -Sev Error -LogData $_
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Guest Invite settings is enabled.' -sev Info
        } else {
            $Object = $CurrentState | Select-Object -Property allowInvitesFrom
            Write-StandardsAlert -message 'Guest Invite settings is not enabled' -object $Object -tenant $tenant -standardName 'GuestInvite' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Guest Invite settings is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            allowInvitesFrom = $CurrentState.allowInvitesFrom
        }
        $ExpectedValue = @{
            allowInvitesFrom = $AllowInvitesFromValue
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.GuestInvite' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'GuestInvite' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
