function Invoke-CIPPStandardProfilePhotos {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ProfilePhotos
    .SYNOPSIS
        (Label) Allow users to set profile photos
    .DESCRIPTION
        (Helptext) Controls whether users can set their own profile photos in Microsoft 365.
        (DocsDescription) Controls whether users can set their own profile photos in Microsoft 365. When disabled, only User and Global administrators can update profile photos for users.
    .NOTES
        CAT
            Global Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.ProfilePhotos.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-01-19
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -ProfilePhotoOptions EnablePhotos and Update-MgBetaAdminPeople
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'ProfilePhotos' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    # Get state value using null-coalescing operator
    $StateValue = $Settings.state.value ?? $Settings.state

    # Input validation
    if ([string]::IsNullOrWhiteSpace($StateValue)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'ProfilePhotos: Invalid state parameter set' -sev Error
        Return
    }

    # true if wanted state is enabled, false if disabled
    $DesiredState = $StateValue -eq 'enabled'

    # Get current Graph policy state
    $Uri = 'https://graph.microsoft.com/beta/admin/people/photoUpdateSettings'
    $CurrentGraphState = New-GraphGetRequest -uri $Uri -tenantid $Tenant
    $UsersCanChangePhotos = if ([string]::IsNullOrWhiteSpace($CurrentGraphState.allowedRoles) ) { $true } else { $false }
    $GraphStateCorrect = $UsersCanChangePhotos -eq $DesiredState

    if ($UsersCanChangePhotos -eq $false -and $DesiredState -eq $false) {
        # Check if the correct roles are present
        $GraphStateCorrect = $CurrentGraphState.allowedRoles -contains '62e90394-69f5-4237-9190-012177145e10' -and $CurrentGraphState.allowedRoles -contains 'fe930be7-5e62-47db-91af-98c3a49a38b1'
    }

    # Get current OWA mailbox policy state
    $CurrentOWAState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OwaMailboxPolicy' -cmdParams @{Identity = 'OwaMailboxPolicy-Default' } -Select 'Identity,SetPhotoEnabled'
    $OWAStateCorrect = $CurrentOWAState.SetPhotoEnabled -eq $DesiredState

    # Check if both states are correct
    $CurrentStatesCorrect = $GraphStateCorrect -eq $true -and $OWAStateCorrect -eq $true

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentStatesCorrect -eq $false) {
            Write-Host 'Settings are not correct'
            try {
                if ($StateValue -eq 'enabled') {
                    Write-Host 'Enabling'
                    # Enable photo updates
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OwaMailboxPolicy' -cmdParams @{Identity = $CurrentOWAState.Identity; SetPhotoEnabled = $true } -useSystemMailbox $true
                    $null = New-GraphPostRequest -uri $Uri -tenant $Tenant -type DELETE -AsApp $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set Profile photo settings to $StateValue" -sev Info

                } else {
                    Write-Host 'Disabling'
                    # Disable photo updates
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OwaMailboxPolicy' -cmdParams @{Identity = $CurrentOWAState.Identity; SetPhotoEnabled = $false } -useSystemMailbox $true

                    $body = @{
                        source       = 'cloud'
                        allowedRoles = @(
                            'fe930be7-5e62-47db-91af-98c3a49a38b1', # Global admin
                            '62e90394-69f5-4237-9190-012177145e10'  # User admin
                        )
                    }
                    $body = ConvertTo-Json -InputObject $body -Depth 5 -Compress
                    $null = New-GraphPostRequest -uri $Uri -tenant $Tenant -body $body -type PATCH -AsApp $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set Profile photo settings to $StateValue" -sev Info
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set profile photo settings to $StateValue. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-Host 'Settings are correct'
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Profile photo settings are already set to the desired state: $StateValue" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentStatesCorrect -eq $false) {
            Write-StandardsAlert -message "Profile photo settings do not match desired state: $StateValue" -object $CurrentOWAState -tenant $Tenant -standardName 'ProfilePhotos' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Profile photo settings do not match desired state: $StateValue" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Profile photo settings match desired state: $StateValue" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'ProfilePhotos' -FieldValue $CurrentStatesCorrect -StoreAs bool -Tenant $Tenant
        if ($CurrentStatesCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = [PSCustomObject]@{
                OwaStateCorrect   = $OWAStateCorrect
                GraphStateCorrect = $GraphStateCorrect
            }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.ProfilePhotos' -FieldValue $FieldValue -Tenant $Tenant
    }
}
