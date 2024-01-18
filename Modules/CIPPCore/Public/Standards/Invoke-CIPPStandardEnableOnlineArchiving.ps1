function Invoke-CIPPStandardEnableOnlineArchiving {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    # {
    #     "name": "standards.EnableOnlineArchiving",
    #     "cat": "Exchange Standards",
    #     "helpText": "Enables the In-Place Online Archive for all UserMailboxes. Before enabling this standard, makes sure you have the correct licensing for all users.",
    #     "addedComponent": [],
    #     "label": "Enable Online Archive for all users",
    #     "impact": "Medium Impact",
    #     "impactColour": "info"
    #   },
    
    $MailboxesNoArchive = New-ExoRequest -tenantid $tenant -cmdlet 'Get-Mailbox' -cmdparams @{ Filter = 'ArchiveGuid -Eq "00000000-0000-0000-0000-000000000000" -AND RecipientTypeDetails -Eq "UserMailbox"' }
    $ValidServicePlans = @(
        '9aaf7827-d63c-4b61-89c3-182f06f82e5c',
        'efb87545-963c-4e0d-99df-69c6916d9eb0',
        '176a09a6-7ec5-4039-ac02-b2791c6ba793'
    )
    $KioskServicePlan = '4a82b400-a79f-41a4-b4e2-e94f5787b113'

    foreach ($User in $MailboxesNoArchive) {
        $UserLicenses = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($User.UserPrincipalName)/licenseDetails" -tenantid $tenant
        $UserLicense = $UserLicenses | Where-Object { $_.servicePlans.servicePlanId -in $ValidServicePlans }
    }

    # TODO: Test if the user has a valid license for Online Archiving. 
    # Loop though all licenses in https://graph.microsoft.com/beta/users/$($User.UserPrincipalName)/licenseDetails and check if the service plan is in $ValidServicePlans
    # If the user has a valid license, add to filtered list
    # If the user does not have a valid license, test if Kiosk license is assigned. 
    
    
    If ($Settings.remediate) {

        if ($null -eq $MailboxesNoArchive) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Online Archiving already enabled for all accounts' -sev Info
        } else {
            try {
                $MailboxesNoArchive | ForEach-Object {
                    try {
                        New-ExoRequest -tenantid $tenant -cmdlet 'Enable-Mailbox' -cmdparams @{ Identity = $_.UserPrincipalName; Archive = $true }
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled Online Archiving for $($_.UserPrincipalName)" -sev Debug
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to Enable Online Archiving for $($_.UserPrincipalName). Error: $($_.exception.message)" -sev Error
                    }
                }
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled Online Archiving for $($MailboxesNoArchive.Count) accounts" -sev Info
        
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to Enable Online Archiving for all accounts. Error: $($_.exception.message)" -sev Error
            }
        }

    }
    if ($Settings.alert) {

        if ($MailboxesNoArchive) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Mailboxes without Online Archiving: $($MailboxesNoArchive.Count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All mailboxes have Online Archiving enabled' -sev Info
        }
    }
    if ($Settings.report) {
        $filtered = $MailboxesNoArchive | Select-Object -Property UserPrincipalName, Archive
        Add-CIPPBPAField -FieldName 'EnableOnlineArchiving' -FieldValue $MailboxesNoArchive -StoreAs json -Tenant $tenant
    }
}
