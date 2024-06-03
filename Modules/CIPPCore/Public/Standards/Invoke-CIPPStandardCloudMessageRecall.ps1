function Invoke-CIPPStandardCloudMessageRecall {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    # Input validation
    if ([string]::isNullOrEmpty($Settings.state) -or $Settings.state -eq 'Select a value') {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'MessageRecallEnabled: Invalid state parameter set' -sev Error
        Exit
    }

    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').MessageRecallEnabled
    $WantedState = if ($Settings.state -eq 'true') { $true } else { $false }
    $StateIsCorrect = if ($CurrentState -eq $WantedState) { $true } else { $false }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($StateIsCorrect -eq $false) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ MessageRecallEnabled = $WantedState } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set the tenant Message Recall state to $($Settings.state)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set the tenant Message Recall state to $($Settings.state). Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant Message Recall state is already set correctly to $($Settings.state)" -sev Info
        }

    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant Message Recall is set correctly to $($Settings.state)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant Message Recall is not set correctly to $($Settings.state)" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        # Default is not set, not set means it's enabled
        if ($null -eq $CurrentState ) { $CurrentState = $true }
        Add-CIPPBPAField -FieldName 'MessageRecall' -FieldValue $CurrentState -StoreAs bool -Tenant $tenant
    }

}