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
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2021-11-16
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -AutoExpandingArchive
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'AutoExpandArchive'

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
            Write-StandardsAlert -message 'Auto Expanding Archives is not enabled' -object @{CurrentState = $CurrentState } -tenant $tenant -standardName 'AutoExpandArchive' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto Expanding Archives is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $CurrentState -eq $true ? $true : $CurrentState
        Set-CIPPStandardsCompareField -FieldName 'standards.AutoExpandArchive' -FieldValue $state -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'AutoExpandingArchive' -FieldValue $CurrentState -StoreAs bool -Tenant $tenant
    }
}
