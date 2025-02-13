function Invoke-CIPPStandardRetentionPolicyTag {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) RetentionPolicyTag
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'RetentionPolicyTag'

    $PolicyName = 'CIPP Deleted Items'
    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RetentionPolicyTag' |
        Where-Object -Property Identity -EQ $PolicyName

    $PolicyState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RetentionPolicy' |
        Where-Object -Property Identity -EQ 'Default MRM Policy'

    $StateIsCorrect =   ($CurrentState.Name -eq $PolicyName) -and
                        ($CurrentState.RetentionEnabled -eq $true) -and
                        ($CurrentState.RetentionAction -eq 'PermanentlyDelete') -and
                        ($CurrentState.AgeLimitForRetention -eq ([timespan]::FromDays($Settings.AgeLimitForRetention))) -and
                        ($CurrentState.Type -eq 'DeletedItems') -and
                        ($PolicyState.RetentionPolicyTagLinks -contains $PolicyName)

    if ($Settings.remediate -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Retention policy tag already correctly configured' -sev Info
        } else {
            $cmdparams = @{
                RetentionEnabled     = $true
                AgeLimitForRetention = $Settings.AgeLimitForRetention
                RetentionAction     = 'PermanentlyDelete'
            }

            if ($CurrentState.Name -eq $PolicyName) {
                try {
                    $cmdparams.Add('Identity', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-RetentionPolicyTag' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Retention policy tag $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Retention policy tag $PolicyName." -sev Error -LogData $_
                }
            } else {
                try {
                    $cmdparams.Add('Name', $PolicyName)
                    $cmdparams.Add('Type', 'DeletedItems')
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-RetentionPolicyTag' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Retention policy tag $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Retention policy tag $PolicyName." -sev Error -LogData $_
                }
            }

            if ($PolicyState.RetentionPolicyTagLinks -notcontains $PolicyName) {
                try {
                    $cmdparams = @{
                        Identity = 'Default MRM Policy'
                        RetentionPolicyTagLinks = @($PolicyState.RetentionPolicyTagLinks + $PolicyName)
                    }
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-RetentionPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Added $PolicyName Retention tag to $($PolicyState.Identity)." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to add $PolicyName Retention tag to $($PolicyState.Identity)." -sev Error -LogData $_.Exception.Message
                }
            }

        }

    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Retention Policy is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Retention Policy is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'RetentionPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
