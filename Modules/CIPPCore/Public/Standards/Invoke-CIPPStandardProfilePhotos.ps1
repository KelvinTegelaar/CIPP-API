function Invoke-CIPPStandardProfilePhotos {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ProfilePhotos
    .SYNOPSIS
        (Label) Allow users to set profile photos
    .DESCRIPTION
        (Helptext) Controls whether users can set their own profile photos in Microsoft 365
        (DocsDescription) Controls whether users can set their own profile photos in Microsoft 365. When disabled, only User and Global administrators can update profile photos for users.
    .NOTES
        CAT
            Global Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"select","multiple":false,"label":"Select value","name":"standards.ProfilePhotos.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -ProfilePhotoOptions EnablePhotos and Update-MgBetaAdminPeople
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>

    param($Tenant, $Settings)

    # Input validation
    if ([string]::IsNullOrWhiteSpace($Settings.state)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'ProfilePhotos: Invalid state parameter set' -sev Error
        Return
    }

    # true if wanted state is enabled, false if disabled
    $DesiredState = $Settings.state -eq 'enabled'

    <#
    HACK This does not work, as the API endpoint is not available via GDAP it seems? It works in the Graph Explorer, but not here.
    The error is: "Authorization failed because of missing requirement(s)."
    I'm keeping the code here for now, so it's much easier to re-enable if Microsoft makes it possible someday. -Bobby
    #>

    # Get current Graph policy state
    # $Uri = 'https://graph.microsoft.com/beta/admin/people/photoUpdateSettings'
    # $CurrentGraphState = New-GraphGetRequest -uri $Uri -tenantid $Tenant
    # $UsersCanChangePhotos = if (($CurrentGraphState.allowedRoles -contains 'fe930be7-5e62-47db-91af-98c3a49a38b1' -and $CurrentGraphState.allowedRoles -contains '62e90394-69f5-4237-9190-012177145e10') -or
    #     $null -ne $CurrentGraphState.allowedRoles) { $false } else { $true }
    # $GraphStateCorrect = $UsersCanChangePhotos -eq $DesiredState


    # Get current OWA mailbox policy state
    $CurrentOWAState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OwaMailboxPolicy' -cmdParams @{Identity = 'OwaMailboxPolicy-Default' } -Select 'Identity,SetPhotoEnabled'
    $OWAStateCorrect = $CurrentOWAState.SetPhotoEnabled -eq $DesiredState
    # $CurrentStatesCorrect = $GraphStateCorrect -eq $true -and $OWAStateCorrect -eq $true
    $CurrentStatesCorrect = $OWAStateCorrect -eq $true

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentStatesCorrect -eq $false) {
            Write-Host 'Settings are not correct'
            try {
                if ($Settings.state -eq 'enabled') {
                    Write-Host 'Enabling'
                    # Enable photo updates
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OwaMailboxPolicy' -cmdParams @{Identity = $CurrentOWAState.Identity; SetPhotoEnabled = $true } -useSystemMailbox $true
                    # $null = New-GraphRequest -uri $Uri -tenant $Tenant -type DELETE
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set Profile photo settings to $($Settings.state)" -sev Info

                } else {
                    Write-Host 'Disabling'
                    # Disable photo updates
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OwaMailboxPolicy' -cmdParams @{Identity = $CurrentOWAState.Identity; SetPhotoEnabled = $false } -useSystemMailbox $true

                    # $body = @{
                    #     source       = 'cloud'
                    #     allowedRoles = @(
                    #         'fe930be7-5e62-47db-91af-98c3a49a38b1', # Global admin
                    #         '62e90394-69f5-4237-9190-012177145e10'  # User admin
                    #     )
                    # }
                    # $body = ConvertTo-Json -InputObject $body -Depth 5 -Compress
                    # $null = New-GraphPostRequest -uri $Uri -tenant $Tenant -body $body -type PATCH -AsApp $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set Profile photo settings to $($Settings.state)" -sev Info
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set profile photo settings to $($Settings.state). Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-Host 'Settings are correct'
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Profile photo settings are already set to the desired state: $($Settings.state)" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentStatesCorrect -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Profile photo settings do not match desired state: $($Settings.state)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Profile photo settings match desired state: $($Settings.state)" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'ProfilePhotos' -FieldValue $CurrentStatesCorrect -StoreAs bool -Tenant $Tenant
    }
}
