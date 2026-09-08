function Invoke-CIPPStandardMigrateOneDriveShortcuts {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) MigrateOneDriveShortcuts
    .SYNOPSIS
        (Label) Migrate OneDrive root shortcuts to the Shortcuts folder
    .DESCRIPTION
        (Helptext) Finds SharePoint library shortcuts sitting in each user's OneDrive root and moves them into the Shortcuts folder (PATCH move into special/shortcuts), matching the optional Microsoft UI location.
        (DocsDescription) Over time Add shortcut to OneDrive can leave many remote library links in the OneDrive root. Microsoft also supports placing those links in an optional Shortcuts folder. This standard lists each enabled member user's OneDrive root with Prefer Include-Feature=AddToOneDrive, then for any remoteItem shortcuts still outside Shortcuts moves them into special/shortcuts. Users without a provisioned OneDrive are skipped. Failures name the user, shortcut, and site URL when available.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        EXECUTIVETEXT
            Keeps employee OneDrive roots tidy by moving SharePoint library shortcuts into the dedicated Shortcuts folder instead of leaving them scattered among personal files.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2026-09-08
        POWERSHELLEQUIVALENT
            PATCH drive/items/{id} parentReference → special/shortcuts
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "SHAREPOINTWAC"
            "SHAREPOINTSTANDARD"
            "SHAREPOINTENTERPRISE"
            "SHAREPOINTENTERPRISE_EDU"
            "SHAREPOINTENTERPRISE_GOV"
            "ONEDRIVEENTERPRISE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'MigrateOneDriveShortcuts' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU', 'SHAREPOINTENTERPRISE_GOV', 'ONEDRIVEENTERPRISE')
    if ($TestResult -eq $false) {
        return $true
    }

    try {
        $AllUsers = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'
        $CandidateUsers = @($AllUsers | Where-Object {
                $_.accountEnabled -eq $true -and
                $_.userType -eq 'Member' -and
                -not [string]::IsNullOrWhiteSpace($_.userPrincipalName)
            })
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the MigrateOneDriveShortcuts state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $UsersWithRootShortcuts = [System.Collections.Generic.List[object]]::new()

    foreach ($User in $CandidateUsers) {
        try {
            $RootShortcuts = @(Invoke-CIPPMigrateOneDriveShortCuts -Username $User.userPrincipalName -TenantFilter $Tenant -ListOnly)
            if ($RootShortcuts.Count -gt 0) {
                $UsersWithRootShortcuts.Add([PSCustomObject]@{
                        userPrincipalName = $User.userPrincipalName
                        displayName       = $User.displayName
                        shortcutCount     = $RootShortcuts.Count
                        shortcuts         = @($RootShortcuts | ForEach-Object { $_.name })
                    })
            }
        } catch {
            # No OneDrive or list failure: skip quietly for scan (migrate helper already classifies no-drive).
            $Msg = $_.Exception.Message
            if ($Msg -notmatch 'No OneDrive found') {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "MigrateOneDriveShortcuts: could not scan $($User.userPrincipalName): $Msg" -sev Warning
            }
        }
    }

    if ($Settings.remediate -eq $true) {
        if ($UsersWithRootShortcuts.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No root OneDrive shortcuts found to migrate.' -sev Info
        } else {
            foreach ($Row in @($UsersWithRootShortcuts)) {
                try {
                    $Result = Invoke-CIPPMigrateOneDriveShortCuts -Username $Row.userPrincipalName -TenantFilter $Tenant
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message $Result -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message $_.Exception.Message -sev Error
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($UsersWithRootShortcuts.Count -gt 0) {
            Write-StandardsAlert -message "Users with OneDrive shortcuts still in the root: $($UsersWithRootShortcuts.Count)" -object $UsersWithRootShortcuts -tenant $Tenant -standardName 'MigrateOneDriveShortcuts' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Users with OneDrive shortcuts still in the root: $($UsersWithRootShortcuts.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No root OneDrive shortcuts found.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $FieldValue = @($UsersWithRootShortcuts | Select-Object userPrincipalName, displayName, shortcutCount, shortcuts)
        $CurrentValue = [PSCustomObject]@{
            UsersWithRootShortcuts = $FieldValue
        }
        $ExpectedValue = [PSCustomObject]@{
            UsersWithRootShortcuts = @()
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.MigrateOneDriveShortcuts' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'MigrateOneDriveShortcuts' -FieldValue $FieldValue -StoreAs json -Tenant $Tenant
    }
}
