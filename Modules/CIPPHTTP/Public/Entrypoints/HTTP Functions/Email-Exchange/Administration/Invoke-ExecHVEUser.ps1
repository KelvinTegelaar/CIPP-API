function Invoke-ExecHVEUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Results = [System.Collections.Generic.List[string]]::new()
    $HVEUserObject = $Request.Body
    $Tenant = $HVEUserObject.TenantFilter
    $Action = $HVEUserObject.Action ?? 'Create'

    try {
        switch ($Action) {
            'Edit' {
                $Identity = $HVEUserObject.Identity
                if ([string]::IsNullOrWhiteSpace($Identity)) {
                    throw 'Identity is required for Edit action'
                }

                # Set-MailUser supports DisplayName and PrimarySmtpAddress for HVE accounts
                $MailUserParams = @{
                    HVEAccount = $true
                    Identity   = $Identity
                }
                if ($HVEUserObject.DisplayName) { $MailUserParams.DisplayName = $HVEUserObject.DisplayName }

                # Build PrimarySmtpAddress from username + domain fields, or use direct value
                if ($HVEUserObject.PrimarySmtpAddress) {
                    $MailUserParams.PrimarySmtpAddress = $HVEUserObject.PrimarySmtpAddress
                } elseif ($HVEUserObject.username -and $HVEUserObject.domain) {
                    $DomainValue = if ($HVEUserObject.domain.value) { $HVEUserObject.domain.value } else { $HVEUserObject.domain }
                    $MailUserParams.PrimarySmtpAddress = "$($HVEUserObject.username)@$DomainValue"
                }

                if ($MailUserParams.Count -gt 2) {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailUser' -cmdParams $MailUserParams
                    $ChangedFields = ($MailUserParams.Keys | Where-Object { $_ -notin 'HVEAccount', 'Identity' }) -join ', '
                    $Results.Add("Updated $ChangedFields for $Identity")
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message "Updated HVE account $Identity ($ChangedFields)" -Sev 'Info'
                }

                # Set-HVEAccountSettings supports ReplyTo only
                if ($HVEUserObject.ReplyTo) {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-HVEAccountSettings' -cmdParams @{
                        Identity = $Identity
                        ReplyTo  = $HVEUserObject.ReplyTo
                    }
                    $Results.Add("Updated reply-to address for $Identity to $($HVEUserObject.ReplyTo)")
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message "Updated HVE reply-to for $Identity" -Sev 'Info'
                }

                if ($Results.Count -eq 0) {
                    $Results.Add("No changes specified for $Identity")
                }
            }
            'AssignBillingPolicy' {
                $Identity = $HVEUserObject.Identity
                if ([string]::IsNullOrWhiteSpace($Identity)) {
                    throw 'Identity is required for AssignBillingPolicy action'
                }

                $PolicyId = if ($HVEUserObject.BillingPolicyId.value) { $HVEUserObject.BillingPolicyId.value } else { $HVEUserObject.BillingPolicyId }
                if ([string]::IsNullOrWhiteSpace($PolicyId)) {
                    throw 'BillingPolicyId is required for AssignBillingPolicy action'
                }

                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-HVEAccountBillingPolicy' -cmdParams @{
                    Identity        = $Identity
                    BillingPolicyId = $PolicyId
                }
                $Results.Add("Assigned billing policy $PolicyId to $Identity")
                Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message "Assigned billing policy to HVE account $Identity" -Sev 'Info'
            }
            'RemoveBillingPolicy' {
                $Identity = $HVEUserObject.Identity
                if ([string]::IsNullOrWhiteSpace($Identity)) {
                    throw 'Identity is required for RemoveBillingPolicy action'
                }

                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-HVEAccountBillingPolicy' -cmdParams @{
                    Identity        = $Identity
                    BillingPolicyId = $null
                }
                $Results.Add("Removed billing policy from $Identity")
                Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message "Removed billing policy from HVE account $Identity" -Sev 'Info'
            }
            'Remove' {
                $Identity = $HVEUserObject.Identity
                if ([string]::IsNullOrWhiteSpace($Identity)) {
                    throw 'Identity is required for Remove action'
                }

                # Get the account details before deleting so we can remove from cache
                $MailUser = $null
                try {
                    $MailUser = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailUser' -cmdParams @{
                        Identity   = $Identity
                        HVEAccount = $true
                    } -Select 'ExternalDirectoryObjectId'
                } catch {
                    Write-Host "Could not retrieve HVE account details for cache cleanup: $($_.Exception.Message)"
                }

                New-ExoRequest -tenantid $Tenant -cmdlet 'Remove-MailUser' -cmdParams @{
                    Identity = $Identity
                    Confirm  = $false
                }

                # Remove from reporting DB cache
                if ($MailUser.ExternalDirectoryObjectId) {
                    try {
                        Remove-CIPPDbItem -TenantFilter $Tenant -Type 'HVEAccounts' -ItemId $MailUser.ExternalDirectoryObjectId
                    } catch {
                        Write-Host "Could not remove HVE account from cache: $($_.Exception.Message)"
                    }
                }

                $Results.Add("Successfully removed HVE account: $Identity")
                Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message "Removed HVE account $Identity" -Sev 'Info'
            }
            default {
                # Create action — original logic

                # Check if Security Defaults are enabled
                try {
                    $SecurityDefaults = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $Tenant
                    if ($SecurityDefaults.isEnabled -eq $true) {
                        $Results.Add('WARNING: Security Defaults are enabled for this tenant. HVE might not function.')
                    }
                } catch {
                    $Results.Add('WARNING: Could not check Security Defaults status. Please verify authentication policies manually.')
                }

                # Create the HVE user using New-MailUser
                $BodyToShip = [pscustomobject] @{
                    Name               = $HVEUserObject.displayName
                    DisplayName        = $HVEUserObject.displayName
                    PrimarySmtpAddress = $HVEUserObject.primarySMTPAddress
                    Password           = $HVEUserObject.password
                    HVEAccount         = $true
                }

                $CreateHVERequest = New-ExoRequest -tenantid $Tenant -cmdlet 'New-MailUser' -cmdParams $BodyToShip
                $Results.Add("Successfully created HVE user: $($HVEUserObject.primarySMTPAddress)")
                Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message "Created HVE user $($HVEUserObject.displayName) with email $($HVEUserObject.primarySMTPAddress)" -Sev 'Info'

                # Try to exclude from Conditional Access policies that block basic authentication
                try {
                    $CAPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $Tenant

                    $BasicAuthPolicies = $CAPolicies | Where-Object {
                        ($_.conditions.clientAppTypes -contains 'exchangeActiveSync' -or
                            $_.conditions.clientAppTypes -contains 'other') -and
                        $_.conditions.applications.includeApplications -contains 'All' -and
                        $_.grantControls.builtInControls -contains 'block'
                    }

                    if ($BasicAuthPolicies) {
                        foreach ($Policy in $BasicAuthPolicies) {
                            try {
                                # Add the HVE user to the exclusions
                                $ExcludedUsers = @($Policy.conditions.users.excludeUsers)
                                if ($CreateHVERequest.ExternalDirectoryObjectId -notin $ExcludedUsers) {

                                    $ExcludeUsers = @($ExcludedUsers + $CreateHVERequest.ExternalDirectoryObjectId)
                                    $UpdateBody = @{
                                        conditions = @{
                                            users = @{
                                                excludeUsers = @($ExcludeUsers | Sort-Object -Unique)
                                            }
                                        }
                                    }

                                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($Policy.id)" -type PATCH -body (ConvertTo-Json -InputObject $UpdateBody -Depth 10) -tenantid $Tenant
                                    $Results.Add("Excluded HVE user from Conditional Access policy: $($Policy.displayName)")
                                    Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message "Excluded HVE user from CA policy: $($Policy.displayName)" -Sev 'Info'
                                }
                            } catch {
                                $ErrorMessage = Get-CippException -Exception $_
                                $Message = "Failed to exclude from CA policy '$($Policy.displayName)': $($ErrorMessage.NormalizedError)"
                                Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -sev 'Warning' -LogData $ErrorMessage
                                $Results.Add($Message)
                            }
                        }
                    } else {
                        $Results.Add('No Conditional Access policies blocking basic authentication found.')
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $Message = "Failed to check/update Conditional Access policies: $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -sev 'Warning' -LogData $ErrorMessage
                    $Results.Add($Message)
                }

            } # end default (Create)
        } # end switch

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to $($Action.ToLower()) HVE user: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results.Add($Message)
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}
