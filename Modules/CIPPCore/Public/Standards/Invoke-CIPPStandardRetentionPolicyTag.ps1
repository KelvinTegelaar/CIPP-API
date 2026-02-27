function Invoke-CIPPStandardRetentionPolicyTag {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) RetentionPolicyTag
    .SYNOPSIS
        (Label) Retention Policy, permanently delete items in Deleted Items after X days
    .DESCRIPTION
        (Helptext) Creates a CIPP - Deleted Items retention policy tag that permanently deletes items in the Deleted Items folder after X days.
        (DocsDescription) Creates a CIPP - Deleted Items retention policy tag that permanently deletes items in the Deleted Items folder after X days.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS M365 5.0 (6.4.1)"
        EXECUTIVETEXT
            Automatically and permanently removes deleted emails after a specified number of days, helping manage storage costs and ensuring compliance with data retention policies. This prevents accumulation of unnecessary deleted items while maintaining a reasonable recovery window for accidentally deleted emails.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.RetentionPolicyTag.AgeLimitForRetention","label":"Retention Days","required":true}
        IMPACT
            High Impact
        ADDEDDATE
            2025-02-02
        POWERSHELLEQUIVALENT
            Set-RetentionPolicyTag
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'RetentionPolicyTag' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $PolicyName = 'CIPP Deleted Items'

    try {
        $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RetentionPolicyTag' |
            Where-Object -Property Identity -EQ $PolicyName

        $PolicyState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RetentionPolicy' |
            Where-Object -Property Identity -EQ 'Default MRM Policy'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the RetentionPolicy state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $CurrentAgeLimitForRetention = ([timespan]$CurrentState.AgeLimitForRetention).TotalDays

    $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
    ($CurrentState.RetentionEnabled -eq $true) -and
    ($CurrentState.RetentionAction -eq 'PermanentlyDelete') -and
    ($CurrentAgeLimitForRetention -eq $Settings.AgeLimitForRetention) -and
    ($CurrentState.Type -eq 'DeletedItems') -and
    ($PolicyState.RetentionPolicyTagLinks -contains $PolicyName)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Retention policy tag already correctly configured' -sev Info
        } else {
            $cmdParams = @{
                RetentionEnabled     = $true
                AgeLimitForRetention = $Settings.AgeLimitForRetention
                RetentionAction      = 'PermanentlyDelete'
            }

            if ($CurrentState.Name -eq $PolicyName) {
                try {
                    $cmdParams.Add('Identity', $PolicyName)
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-RetentionPolicyTag' -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Retention policy tag $PolicyName." -sev Info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Retention policy tag $PolicyName." -sev Error -LogData $ErrorMessage
                }
            } else {
                try {
                    $cmdParams.Add('Name', $PolicyName)
                    $cmdParams.Add('Type', 'DeletedItems')
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-RetentionPolicyTag' -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Retention policy tag $PolicyName." -sev Info
                } catch {

                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Retention policy tag $PolicyName." -sev Error -LogData $ErrorMessage
                }
            }

            if ($PolicyState.RetentionPolicyTagLinks -notcontains $PolicyName) {
                try {
                    $cmdParams = @{
                        Identity                = 'Default MRM Policy'
                        RetentionPolicyTagLinks = @($PolicyState.RetentionPolicyTagLinks + $PolicyName)
                    }
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-RetentionPolicy' -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Added $PolicyName Retention tag to $($PolicyState.Identity)." -sev Info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to add $PolicyName Retention tag to $($PolicyState.Identity)." -sev Error -LogData $ErrorMessage
                }
            }

        }

    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Retention Policy is enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Retention Policy is not enabled' -object $CurrentState -tenant $Tenant -standardName 'RetentionPolicyTag' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Retention Policy is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'RetentionPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant

        $CurrentValue = @{
            retentionEnabled     = $CurrentState.RetentionEnabled
            retentionAction      = $CurrentState.RetentionAction
            ageLimitForRetention = $CurrentAgeLimitForRetention
            type                 = $CurrentState.Type
            policyTagLinked      = $PolicyState.RetentionPolicyTagLinks -contains $PolicyName

        }
        $ExpectedValue = @{
            retentionEnabled     = $true
            retentionAction      = 'PermanentlyDelete'
            ageLimitForRetention = $Settings.AgeLimitForRetention
            type                 = 'DeletedItems'
            policyTagLinked      = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.RetentionPolicyTag' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
