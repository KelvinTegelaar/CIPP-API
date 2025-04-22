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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#high-impact
    #>

    param($Tenant, $Settings)

    $PolicyName = 'CIPP Deleted Items'
    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RetentionPolicyTag' |
    Where-Object -Property Identity -EQ $PolicyName

    $PolicyState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RetentionPolicy' |
    Where-Object -Property Identity -EQ 'Default MRM Policy'

    $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
    ($CurrentState.RetentionEnabled -eq $true) -and
    ($CurrentState.RetentionAction -eq 'PermanentlyDelete') -and
    ($CurrentState.AgeLimitForRetention -eq ([timespan]::FromDays($Settings.AgeLimitForRetention))) -and
    ($CurrentState.Type -eq 'DeletedItems') -and
    ($PolicyState.RetentionPolicyTagLinks -contains $PolicyName)

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

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

        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = @{ CurrentState = $CurrentState; PolicyState = $PolicyState }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.RetentionPolicyTag' -FieldValue $FieldValue -Tenant $Tenant
    }

}
