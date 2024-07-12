function Invoke-CIPPStandardAutoExpandArchive {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AutoExpandArchive
    .SYNOPSIS
        (Label) Enable Auto-expanding archives
    .DESCRIPTION
        (Helptext) Enables auto-expanding archives for the tenant
        (DocsDescription) Enables auto-expanding archives for the tenant. Does not enable archives for users.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -AutoExpandingArchive
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').AutoExpandingArchiveEnabled

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentState) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto Expanding Archive is already enabled.' -sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{AutoExpandingArchive = $true }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Added Auto Expanding Archive.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Auto Expanding Archives. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentState) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto Expanding Archives is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto Expanding Archives is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'AutoExpandingArchive' -FieldValue $CurrentState -StoreAs bool -Tenant $tenant
    }
}
