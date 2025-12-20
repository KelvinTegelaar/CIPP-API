function Invoke-CIPPStandarddisableMacSync {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) disableMacSync
    .SYNOPSIS
        (Label) Do not allow Mac devices to sync using OneDrive
    .DESCRIPTION
        (Helptext) Disables the ability for Mac devices to sync with OneDrive.
        (DocsDescription) Disables the ability for Mac devices to sync with OneDrive.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        EXECUTIVETEXT
            Prevents Mac computers from synchronizing files with OneDrive, typically implemented for security or compliance reasons in Windows-centric environments. This restriction helps maintain standardized device management while potentially limiting collaboration for Mac users.
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2022-06-15
        POWERSHELLEQUIVALENT
            Update-MgAdminSharePointSetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'disableMacSync' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU','ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'disableMacSync'

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableMacSync state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.isMacSyncAppEnabled -eq $true) {
            try {
                $body = '{"isMacSyncAppEnabled": false}'
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled Mac OneDrive Sync' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Mac OneDrive Sync: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Mac OneDrive Sync is already disabled' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.isMacSyncAppEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Mac OneDrive Sync is disabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Mac OneDrive Sync is not disabled' -object $CurrentInfo -tenant $tenant -standardName 'disableMacSync' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Mac OneDrive Sync is not disabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentInfo.isMacSyncAppEnabled = -not $CurrentInfo.isMacSyncAppEnabled
        Set-CIPPStandardsCompareField -FieldName 'standards.disableMacSync' -FieldValue $CurrentInfo.isMacSyncAppEnabled -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'MacSync' -FieldValue $CurrentInfo.isMacSyncAppEnabled -StoreAs bool -Tenant $tenant
    }
}
