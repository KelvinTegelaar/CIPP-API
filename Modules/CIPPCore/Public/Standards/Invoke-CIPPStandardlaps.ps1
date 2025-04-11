function Invoke-CIPPStandardlaps {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) laps
    .SYNOPSIS
        (Label) Enable LAPS on the tenant
    .DESCRIPTION
        (Helptext) Enables the tenant to use LAPS. You must still create a policy for LAPS to be active on all devices. Use the template standards to deploy this by default.
        (DocsDescription) Enables the LAPS functionality on the tenant. Prerequisite for using Windows LAPS via Azure AD.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2023-04-25
        POWERSHELLEQUIVALENT
            Portal or Graph API
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'laps'

    $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant

    If ($Settings.remediate -eq $true) {
        try {
            $PreviousSetting.localAdminPassword.isEnabled = $true
            $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting -Depth 10
            New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS has been enabled.' -sev Info
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            $PreviousSetting.localAdminPassword.isEnabled = $false
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable LAPS: $ErrorMessage" -sev Error
        }
    }
    if ($Settings.alert -eq $true) {
        if ($PreviousSetting.localAdminPassword.isEnabled) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'LAPS is not enabled' -object $PreviousSetting -tenant $Tenant -standardName 'laps' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $PreviousSetting.localAdminPassword.isEnabled ? $true : $false
        Set-CIPPStandardsCompareField -FieldName 'standards.laps' -FieldValue $state -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'laps' -FieldValue $PreviousSetting.localAdminPassword.isEnabled -StoreAs bool -Tenant $tenant
    }
}
