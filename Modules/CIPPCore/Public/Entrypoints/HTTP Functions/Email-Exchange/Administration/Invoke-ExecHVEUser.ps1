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

    try {
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
            # Get all Conditional Access policies
            $CAPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $Tenant

            $BasicAuthPolicies = $CAPolicies | Where-Object {
                $_.conditions.clientAppTypes -contains 'exchangeActiveSync' -or
                $_.conditions.clientAppTypes -contains 'other' -or
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
                        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Warning' -LogData $ErrorMessage
                        $Results.Add($Message)
                    }
                }
            } else {
                $Results.Add('No Conditional Access policies blocking basic authentication found.')
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Failed to check/update Conditional Access policies: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Warning' -LogData $ErrorMessage
            $Results.Add($Message)
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to create HVE user: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results.Add($Message)
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}
