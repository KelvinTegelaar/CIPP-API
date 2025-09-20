function Invoke-CIPPStandardQuarantineTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) QuarantineTemplate
    .SYNOPSIS
        (Label) Custom Quarantine Policy
    .DESCRIPTION
        (Helptext) This standard creates a Custom Quarantine Policies that can be used in Anti-Spam and all MDO365 policies. Quarantine Policies can be used to specify recipients permissions, enable end-user spam notifications, and specify the release action preference
        (DocsDescription) This standard creates a Custom Quarantine Policies that can be used in Anti-Spam and all MDO365 policies. Quarantine Policies can be used to specify recipients permissions, enable end-user spam notifications, and specify the release action preference
    .NOTES
        CAT
            Defender Standards
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":true,"name":"displayName","label":"Quarantine Display Name","required":true}
            {"type":"switch","label":"Enable end-user spam notifications","name":"ESNEnabled","defaultValue":true,"required":false}
            {"type":"select","multiple":false,"label":"Select release action preference","name":"ReleaseAction","options":[{"label":"Allow recipients to request a message to be released from quarantine","value":"PermissionToRequestRelease"},{"label":"Allow recipients to release a message from quarantine","value":"PermissionToRelease"}]}
            {"type":"switch","label":"Include Messages From Blocked Sender Address","name":"IncludeMessagesFromBlockedSenderAddress","defaultValue":false,"required":false}
            {"type":"switch","label":"Allow recipients to delete message","name":"PermissionToDelete","defaultValue":false,"required":false}
            {"type":"switch","label":"Allow recipients to preview message","name":"PermissionToPreview","defaultValue":false,"required":false}
            {"type":"switch","label":"Allow recipients to block Sender Address","name":"PermissionToBlockSender","defaultValue":false,"required":false}
            {"type":"switch","label":"Allow recipients to whitelist Sender Address","name":"PermissionToAllowSender","defaultValue":false,"required":false}
        MULTIPLE
            True
        IMPACT
            Low Impact
        ADDEDDATE
            2025-05-16
        POWERSHELLEQUIVALENT
            Set-QuarantinePolicy or New-QuarantinePolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'QuarantineTemplate' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    $APIName = 'Standards'

    try {
        # Get the current custom quarantine policies
        $CurrentPolicies = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-QuarantinePolicy' | Where-Object -Property Guid -ne '00000000-0000-0000-0000-000000000000' -ErrorAction Stop

        # Compare the settings from standard with the current policies
        $CompareList = foreach ($Policy in $Settings) {
            try {
                # Create hashtable with desired Quarantine Setting
                $EndUserQuarantinePermissions   = @{
                    # ViewHeader and Download are set to false because the value 0 or 1 does nothing per Microsoft documentation
                    PermissionToViewHeader = $false
                    PermissionToDownload  = $false
                    PermissionToBlockSender = $Policy.PermissionToBlockSender
                    PermissionToDelete  = $Policy.PermissionToDelete
                    PermissionToPreview = $Policy.PermissionToPreview
                    PermissionToRelease = $Policy.ReleaseAction -eq "PermissionToRelease" ? $true : $false
                    PermissionToRequestRelease  = $Policy.ReleaseAction -eq "PermissionToRequestRelease" ? $true : $false
                    PermissionToAllowSender = $Policy.PermissionToAllowSender
                }

                # If the Quarantine Policy already exists
                if ($Policy.displayName.value -in $CurrentPolicies.Name) {
                    #Get the current policy and convert EndUserQuarantinePermissions from string to hashtable for compare
                    $ExistingPolicy = $CurrentPolicies | Where-Object -Property Name -eq $Policy.displayName.value
                    $ExistingPolicyEndUserQuarantinePermissions = Convert-QuarantinePermissionsValue -InputObject $ExistingPolicy.EndUserQuarantinePermissions -ErrorAction Stop

                    #Compare the current policy
                    $StateIsCorrect = ($ExistingPolicy.Name -eq $Policy.displayName.value) -and
                                ($ExistingPolicy.ESNEnabled -eq $Policy.ESNEnabled) -and
                                ($ExistingPolicy.IncludeMessagesFromBlockedSenderAddress -eq $Policy.IncludeMessagesFromBlockedSenderAddress) -and
                                (!(Compare-Object @($ExistingPolicyEndUserQuarantinePermissions.values) @($EndUserQuarantinePermissions.values)))

                    # If the current policy is correct
                    if ($StateIsCorrect -eq $true) {
                        [PSCustomObject]@{
                            missing         = $false
                            StateIsCorrect  = $StateIsCorrect
                            Action          = "None"
                            displayName     = $Policy.displayName.value
                            EndUserQuarantinePermissions = $EndUserQuarantinePermissions
                            ESNEnabled      = $Policy.ESNEnabled
                            IncludeMessagesFromBlockedSenderAddress = $Policy.IncludeMessagesFromBlockedSenderAddress
                            remediate       = $Policy.remediate
                            alert           = $Policy.alert
                            report          = $Policy.report
                        }
                    }
                    #If the current policy doesn't match the desired settings
                    else {
                        [PSCustomObject]@{
                            missing         = $false
                            StateIsCorrect  = $StateIsCorrect
                            Action          = "Update"
                            displayName     = $Policy.displayName.value
                            EndUserQuarantinePermissions = $EndUserQuarantinePermissions
                            ESNEnabled      = $Policy.ESNEnabled
                            IncludeMessagesFromBlockedSenderAddress = $Policy.IncludeMessagesFromBlockedSenderAddress
                            remediate       = $Policy.remediate
                            alert           = $Policy.alert
                            report          = $Policy.report
                        }
                    }
                }
                #If no existing Quarantine Policy with the same name was found
                else {
                    [PSCustomObject]@{
                        missing         = $true
                        StateIsCorrect  = $false
                        Action          = "Create"
                        displayName     = $Policy.displayName.value
                        EndUserQuarantinePermissions = $EndUserQuarantinePermissions
                        ESNEnabled      = $Policy.ESNEnabled
                        IncludeMessagesFromBlockedSenderAddress = $Policy.IncludeMessagesFromBlockedSenderAddress
                        remediate       = $Policy.remediate
                        alert           = $Policy.alert
                        report          = $Policy.report
                    }
                }
            }
            catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $Message = "Failed to compare Quarantine policy $($Policy.displayName.value), Error: $ErrorMessage"
                Write-LogMessage -API $APIName -tenant $tenant -message $Message -sev 'Error'
                Return $Message
            }
        }


        If ($true -in $Settings.remediate) {
            # Remediate each policy which is incorrect or missing
            foreach ($Policy in $CompareList | Where-Object { $_.remediate -EQ $true -and $_.StateIsCorrect -eq $false }) {
                try {
                    # Parameters for splatting to Set-CIPPQuarantinePolicy
                    $Params = @{
                        Action = $Policy.Action
                        Identity = $Policy.displayName
                        EndUserQuarantinePermissions = $Policy.EndUserQuarantinePermissions
                        ESNEnabled = $Policy.ESNEnabled
                        IncludeMessagesFromBlockedSenderAddress = $Policy.IncludeMessagesFromBlockedSenderAddress
                        tenantFilter = $Tenant
                        APIName = $APIName
                    }

                    try {
                        Set-CIPPQuarantinePolicy @Params
                        Write-LogMessage -API $APIName -tenant $Tenant -message "$($Policy.Action)d Custom Quarantine Policy '$($Policy.displayName)'" -sev Info
                    }
                    catch {
                        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                        Write-LogMessage -API $APIName -tenant $tenant -message "Failed to $($Policy.Action) Quarantine policy $($Policy.displayName), Error: $ErrorMessage" -sev 'Error'
                    }
                }
                catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API $APIName -tenant $tenant -message "Failed to create or update Quarantine policy $($Policy.displayName), Error: $ErrorMessage" -sev 'Error'
                }
            }
        }

        if ($true -in $Settings.alert) {
            foreach ($Policy in $CompareList | Where-Object -Property alert -EQ $true) {
                if ($Policy.StateIsCorrect) {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "Quarantine policy $($Policy.displayName) has the correct configuration." -sev Info
                }
                else {
                    if ($Policy.missing) {
                        $CurrentInfo = $Policy | Select-Object -Property displayName, missing
                        Write-StandardsAlert -message "Quarantine policy $($Policy.displayName) is missing." -object $CurrentInfo -tenant $Tenant -standardName 'QuarantineTemplate' -standardId $Settings.templateId
                        Write-LogMessage -API $APIName -tenant $Tenant -message "Quarantine policy $($Policy.displayName) is missing." -sev info
                    }
                    else {
                        $CurrentInfo = $CurrentPolicies | Where-Object -Property Name -eq $Policy.displayName | Select-Object -Property Name, ESNEnabled, IncludeMessagesFromBlockedSenderAddress, EndUserQuarantinePermissions
                        Write-StandardsAlert -message "Quarantine policy $($Policy.displayName) does not match the expected configuration." -object $CurrentInfo -tenant $Tenant -standardName 'QuarantineTemplate' -standardId $Settings.templateId
                        Write-LogMessage -API $APIName -tenant $Tenant -message "Quarantine policy $($Policy.displayName) does not match the expected configuration. We've generated an alert" -sev info
                    }
                }
            }
        }

        if ($true -in $Settings.report) {
            foreach ($Policy in $CompareList | Where-Object -Property report -EQ $true) {
                # Convert displayName to hex to avoid invalid characters "/, \, #, ?" which are not allowed in RowKey, but "\, #, ?" can be used in quarantine displayName
                $HexName = -join ($Policy.displayName.ToCharArray() | ForEach-Object { '{0:X2}' -f [int][char]$_ })
                Set-CIPPStandardsCompareField -FieldName "standards.QuarantineTemplate.$HexName" -FieldValue $Policy.StateIsCorrect -TenantFilter $Tenant
            }
        }
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API $APIName -tenant $tenant -message "Failed to create or update Quarantine policy/policies, Error: $ErrorMessage" -sev 'Error'
    }
}
