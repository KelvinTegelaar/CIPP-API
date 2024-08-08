function Invoke-CIPPStandardintuneBrandingProfile {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) intuneBrandingProfile
    .SYNOPSIS
        (Label) Set Intune Company Portal branding profile
    .DESCRIPTION
        (Helptext) Sets the branding profile for the Intune Company Portal app. This is a tenant wide setting and overrules any settings set on the app level.
        (DocsDescription) Sets the branding profile for the Intune Company Portal app. This is a tenant wide setting and overrules any settings set on the app level.
    .NOTES
        CAT
            Intune Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"input","name":"standards.intuneBrandingProfile.displayName","label":"Organization name"}
            {"type":"boolean","name":"standards.intuneBrandingProfile.showLogo","label":"Show logo"}
            {"type":"boolean","name":"standards.intuneBrandingProfile.showDisplayNameNextToLogo","label":"Show organization name next to logo"}
            {"type":"input","name":"standards.intuneBrandingProfile.contactITName","label":"Contact IT name"}
            {"type":"input","name":"standards.intuneBrandingProfile.contactITPhoneNumber","label":"Contact IT phone number"}
            {"type":"input","name":"standards.intuneBrandingProfile.contactITEmailAddress","label":"Contact IT email address"}
            {"type":"input","name":"standards.intuneBrandingProfile.contactITNotes","label":"Contact IT notes"}
            {"type":"input","name":"standards.intuneBrandingProfile.onlineSupportSiteName","label":"Online support site name"}
            {"type":"input","name":"standards.intuneBrandingProfile.onlineSupportSiteUrl","label":"Online support site URL"}
            {"type":"input","name":"standards.intuneBrandingProfile.privacyUrl","label":"Privacy statement URL"}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'intuneBrandingProfile'

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/intuneBrandingProfiles/c3a59481-1bf2-46ce-94b3-66eec07a8d60/' -tenantid $Tenant -AsApp $true

    $StateIsCorrect = ((-not $Settings.displayName) -or ($CurrentState.displayName -eq $Settings.displayName)) -and
                        ((-not $Settings.showLogo) -or ($CurrentState.showLogo -eq $Settings.showLogo)) -and
                        ((-not $Settings.showDisplayNameNextToLogo) -or ($CurrentState.showDisplayNameNextToLogo -eq $Settings.showDisplayNameNextToLogo)) -and
                        ((-not $Settings.contactITName) -or ($CurrentState.contactITName -eq $Settings.contactITName)) -and
                        ((-not $Settings.contactITPhoneNumber) -or ($CurrentState.contactITPhoneNumber -eq $Settings.contactITPhoneNumber)) -and
                        ((-not $Settings.contactITEmailAddress) -or ($CurrentState.contactITEmailAddress -eq $Settings.contactITEmailAddress)) -and
                        ((-not $Settings.contactITNotes) -or ($CurrentState.contactITNotes -eq $Settings.contactITNotes)) -and
                        ((-not $Settings.onlineSupportSiteName) -or ($CurrentState.onlineSupportSiteName -eq $Settings.onlineSupportSiteName)) -and
                        ((-not $Settings.onlineSupportSiteUrl) -or ($CurrentState.onlineSupportSiteUrl -eq $Settings.onlineSupportSiteUrl)) -and
                        ((-not $Settings.privacyUrl) -or ($CurrentState.privacyUrl -eq $Settings.privacyUrl))

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Intune Branding Profile is already correctly configured' -sev Info
        } else {
            $Body = @{}
            if ($Settings.displayName) { $Body.displayName = $Settings.displayName }
            if ($Settings.showLogo) { $Body.showLogo = $Settings.showLogo }
            if ($Settings.showDisplayNameNextToLogo) { $Body.showDisplayNameNextToLogo = $Settings.showDisplayNameNextToLogo }
            if ($Settings.contactITName) { $Body.contactITName = $Settings.contactITName }
            if ($Settings.contactITPhoneNumber) { $Body.contactITPhoneNumber = $Settings.contactITPhoneNumber }
            if ($Settings.contactITEmailAddress) { $Body.contactITEmailAddress = $Settings.contactITEmailAddress }
            if ($Settings.contactITNotes) { $Body.contactITNotes = $Settings.contactITNotes }
            if ($Settings.onlineSupportSiteName) { $Body.onlineSupportSiteName = $Settings.onlineSupportSiteName }
            if ($Settings.onlineSupportSiteUrl) { $Body.onlineSupportSiteUrl = $Settings.onlineSupportSiteUrl }
            if ($Settings.privacyUrl) { $Body.privacyUrl = $Settings.privacyUrl }

            $cmdparams = @{
                tenantid    = $tenant
                uri         = 'https://graph.microsoft.com/beta/deviceManagement/intuneBrandingProfiles/c3a59481-1bf2-46ce-94b3-66eec07a8d60/'
                AsApp       = $true
                Type        = 'PATCH'
                Body        = ($Body | ConvertTo-Json)
                ContentType = 'application/json; charset=utf-8'
            }

            try {
                New-GraphPostRequest @cmdparams
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Successfully updated Intune Branding Profile' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to update Intune Branding Profile. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Intune Branding Profile is correctly configured' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Intune Branding Profile is not correctly configured' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'intuneBrandingProfile' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
