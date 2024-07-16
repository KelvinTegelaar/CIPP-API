function Invoke-CIPPStandardsharingDomainRestriction {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) sharingDomainRestriction
    .SYNOPSIS
        (Label) Restrict sharing to a specific domain
    .DESCRIPTION
        (Helptext) Restricts sharing to only users with the specified domain. This is useful for organizations that only want to share with their own domain.
        (DocsDescription) Restricts sharing to only users with the specified domain. This is useful for organizations that only want to share with their own domain.
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "highimpact"
            "CIS"
        ADDEDCOMPONENT
            {"type":"Select","name":"standards.sharingDomainRestriction.Mode","label":"Limit external sharing by domains","values":[{"label":"Off","value":"none"},{"label":"Restirct sharing to specific domains","value":"allowList"},{"label":"Block sharing to specific domains","value":"blockList"}]}
            {"type":"input","name":"standards.sharingDomainRestriction.Domains","label":"Domains to allow/block, comma separated"}
        IMPACT
            High Impact
        POWERSHELLEQUIVALENT
            Update-MgAdminSharepointSetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    if ($Settings.Mode -eq 'none' -or $null -eq $Settings.Mode) {
        $StateIsCorrect = $CurrentState.sharingDomainRestrictionMode -eq 'none'
    } else {
        $SelectedDomains = [String[]]$Settings.Domains.Split(',').Trim()
        $StateIsCorrect = ($CurrentState.sharingDomainRestrictionMode -eq $Settings.Mode) -and
                          ($Settings.Mode -eq 'allowList' -and (!(Compare-Object -ReferenceObject $CurrentState.sharingAllowedDomainList -DifferenceObject $SelectedDomains))) -or
                          ($Settings.Mode -eq 'blockList' -and (!(Compare-Object -ReferenceObject $CurrentState.sharingBlockedDomainList -DifferenceObject $SelectedDomains)))
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sharing Domain Restriction is already correctly configured' -sev Info
        } else {
            $Body = @{
                sharingDomainRestrictionMode = $Settings.Mode
            }

            if ($Settings.Mode -eq 'AllowList') {
                $Body.Add('sharingAllowedDomainList', $SelectedDomains)
            } elseif ($Settings.Mode -eq 'BlockList') {
                $Body.Add('sharingBlockedDomainList', $SelectedDomains)
            }

            $cmdparams = @{
                tenantid    = $tenant
                uri         = 'https://graph.microsoft.com/beta/admin/sharepoint/settings'
                AsApp       = $true
                Type        = 'PATCH'
                Body        = ($Body | ConvertTo-Json)
                ContentType = 'application/json'
            }

            try {
                New-GraphPostRequest @cmdparams
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Successfully updated Sharing Domain Restriction settings' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to update Sharing Domain Restriction settings. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sharing Domain Restriction is correctly configured' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sharing Domain Restriction is not correctly configured' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'sharingDomainRestriction' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
