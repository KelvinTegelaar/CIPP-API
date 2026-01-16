function Invoke-CIPPStandardAutoArchiveMailbox {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AutoArchiveMailbox
    .SYNOPSIS
        (Label) Set auto enable archive mailbox state
    .DESCRIPTION
        (Helptext) Enables or disables the tenant policy that automatically provisions an archive mailbox when a user's primary mailbox reaches 90% of its quota.
        (DocsDescription) Enables or disables the tenant policy that automatically provisions an archive mailbox when a user's primary mailbox reaches 90% of its quota. This is separate from auto-archiving thresholds and does not enable archives for all users immediately.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Automatically provisions archive mailboxes only when users reach 90% of their mailbox capacity, reducing manual intervention and preventing mailbox quota issues without enabling archives for everyone.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.AutoArchiveMailbox.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-01-16
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -AutoEnableArchiveMailbox \$true\|\$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'AutoArchiveMailbox' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    }

    $StateValue = $Settings.state.value ?? $Settings.state

    if ([string]::IsNullOrWhiteSpace($StateValue)) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'AutoArchiveMailbox: Invalid state parameter set' -Sev Error
        return
    }

    $DesiredState = $StateValue -eq 'enabled'

    try {
        $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' -Select 'AutoEnableArchiveMailbox').AutoEnableArchiveMailbox
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the AutoArchiveMailbox state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    $CorrectState = $CurrentState -eq $DesiredState

    $ExpectedValue = [PSCustomObject]@{
        AutoEnableArchiveMailbox = $DesiredState
    }
    $CurrentValue = [PSCustomObject]@{
        AutoEnableArchiveMailbox = $CurrentState
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CorrectState) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Auto enable archive mailbox is already set to $StateValue." -Sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ AutoEnableArchiveMailbox = $DesiredState }
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Auto enable archive mailbox has been set to $StateValue." -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set auto enable archive mailbox to $StateValue. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CorrectState) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Auto enable archive mailbox is correctly set to $StateValue." -Sev Info
        } else {
            Write-StandardsAlert -message "Auto enable archive mailbox is set to $CurrentState but should be $DesiredState." -object @{ CurrentState = $CurrentState; DesiredState = $DesiredState } -tenant $Tenant -standardName 'AutoArchiveMailbox' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Auto enable archive mailbox is set to $CurrentState but should be $DesiredState." -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.AutoArchiveMailbox' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AutoArchiveMailbox' -FieldValue $CurrentState -StoreAs bool -Tenant $Tenant
    }
}
