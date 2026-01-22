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
        EXECUTIVETEXT
            Enables automatic expansion of email archive storage when users approach their archive limits, ensuring continuous email retention without manual intervention. This prevents email storage issues and maintains compliance with data retention policies without requiring ongoing administrative management.
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
    $TestResult = Test-CIPPStandardLicense -StandardName 'AutoExpandArchive' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'AutoExpandArchive'

    try {
        $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').AutoExpandingArchiveEnabled
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the AutoExpandArchive state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    $ExpectedValue = [PSCustomObject]@{
        AutoExpandingArchive = $true
    }
    $CurrentValue = [PSCustomObject]@{
        AutoExpandingArchive = $CurrentState
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentState) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto Expanding Archive is already enabled.' -sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{AutoExpandingArchive = $true }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Added Auto Expanding Archive.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Auto Expanding Archives. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
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
        Set-CIPPStandardsCompareField -FieldName 'standards.AutoExpandArchive' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'AutoExpandingArchive' -FieldValue $CurrentState -StoreAs bool -Tenant $tenant
    }
}
