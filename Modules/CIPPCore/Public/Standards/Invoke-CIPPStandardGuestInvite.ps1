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
            "mediumimpact"
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"label":"Who can send invites?","name":"standards.GuestInvite.allowInvitesFrom","options":[{"label":"Everyone","value":"everyone"},{"label":"Admins, Guest inviters and All Members","value":"adminsGuestInvitersAndAllMembers"},{"label":"Admins and Guest inviters","value":"adminsAndGuestInviters"},{"label":"None","value":"none"}]}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#medium-impact
    #>

    param($Tenant, $Settings)

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant

    if ($null -eq $Settings.allowInvitesFrom) { $Settings.allowInvitesFrom = 'Everyone' } # none, adminsAndGuestInviters, adminsGuestInvitersAndAllMembers, everyone
    $StateIsCorrect =   ($CurrentState.allowInvitesFrom -eq $Settings.allowInvitesFrom)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Guest Invite settings is already applied correctly.' -Sev Info
        } else {
            try {
                $GraphRequest = @{
                    tenantID    = $Tenant
                    uri         = "https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy"
                    AsApp       = $false
                    Type        = 'PATCH'
                    ContentType = 'application/json; charset=utf-8'
                    Body        = [pscustomobject]@{
                        allowInvitesFrom = $Settings.allowInvitesFrom
                    } | ConvertTo-Json -Compress
                }
                New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Successfully updated Guest Invite setting to $($Settings.allowInvitesFrom)" -Sev Info
            } catch {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to update Guest Invite setting to $($Settings.allowInvitesFrom)" -Sev Error -LogData $_
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Guest Invite settings is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Guest Invite settings is not enabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'GuestInvite' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
