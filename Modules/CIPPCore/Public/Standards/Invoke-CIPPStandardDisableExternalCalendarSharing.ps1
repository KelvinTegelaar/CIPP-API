function Invoke-CIPPStandardDisableExternalCalendarSharing {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableExternalCalendarSharing
    .SYNOPSIS
        (Label) Disable external calendar sharing
    .DESCRIPTION
        (Helptext) Disables the ability for users to share their calendar with external users. Only for the default policy, so exclusions can be made if needed.
        (DocsDescription) Disables external calendar sharing for the entire tenant. This is not a widely used feature, and it's therefore unlikely that this will impact users. Only for the default policy, so exclusions can be made if needed by making a new policy and assigning it to users.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS M365 5.0 (1.3.3)"
            "exo_individualsharing"
        EXECUTIVETEXT
            Prevents employees from sharing their calendars with external parties, protecting sensitive meeting information and internal schedules from unauthorized access. This security measure helps maintain confidentiality of business activities while still allowing internal collaboration.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-01-08
        POWERSHELLEQUIVALENT
            Get-SharingPolicy \| Set-SharingPolicy -Enabled \$False
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableExternalCalendarSharing' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SharingPolicy' |
            Where-Object { $_.Default -eq $true }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableExternalCalendarSharing state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo.Enabled) {
            $BulkRequest = foreach ($Policy in $CurrentInfo) {
                @{
                    CmdletInput = @{
                        CmdletName = 'Set-SharingPolicy'
                        Parameters = @{ Identity = $Policy.Id ; Enabled = $false }
                    }
                }
            }
            $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($BulkRequest) -useSystemMailbox $true
            foreach ($Result in $BatchResults) {
                if ($Result.error) {
                    $ErrorMessage = Get-NormalizedError -Message $Result.error
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable external calendar sharing. Error: $ErrorMessage" -sev Error
                }
            }
            $SuccessCount = ($BatchResults | Where-Object { -not $_.error }).Count
            if ($SuccessCount -gt 0) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully disabled external calendar sharing for $SuccessCount policies" -sev Info
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'External calendar sharing is already disabled' -sev Info

        }

    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.Enabled) {
            Write-StandardsAlert -message 'External calendar sharing is enabled' -object ($CurrentInfo | Select-Object enabled) -tenant $tenant -standardName 'DisableExternalCalendarSharing' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'External calendar sharing is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'External calendar sharing is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentStatus = -not $CurrentInfo.Enabled

        $CurrentValue = [PSCustomObject]@{
            ExternalCalendarSharingDisabled = $CurrentStatus
        }
        $ExpectedValue = [PSCustomObject]@{
            ExternalCalendarSharingDisabled = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableExternalCalendarSharing' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'ExternalCalendarSharingDisabled' -FieldValue $CurrentStatus -StoreAs bool -Tenant $tenant
    }
}
