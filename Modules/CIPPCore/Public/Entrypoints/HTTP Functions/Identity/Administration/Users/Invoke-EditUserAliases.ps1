using namespace System.Net

function Invoke-EditUserAliases {
    <#
    .SYNOPSIS
    Manage user email aliases in Microsoft 365/Exchange Online
    
    .DESCRIPTION
    Adds, removes, or sets the primary email alias for a user in Microsoft 365/Exchange Online, supporting validation, normalization, and error handling.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    
    .NOTES
    Group: Identity Management
    Summary: Edit User Aliases
    Description: Adds, removes, or sets the primary email alias for a user in Microsoft 365/Exchange Online, supporting validation, normalization, and error handling. Handles mailbox lookup, proxy address management, and logs all actions.
    Tags: Identity,User,Aliases,Exchange Online,Microsoft 365
    Parameter: id (string) [body] - User ID to manage aliases for
    Parameter: tenantFilter (string) [body] - Target tenant identifier
    Parameter: AddedAliases (string) [body] - Comma-separated list of aliases to add
    Parameter: RemovedAliases (string) [body] - Comma-separated list of aliases to remove
    Parameter: MakePrimary (string) [body] - Email address to set as primary
    Response: Returns a response object with the following properties:
    Response: - Results (array): Array of status messages for each alias operation
    Response: On success: Array of success messages for each operation
    Response: On error: Error message with HTTP 400 status
    Example: {
      "Results": [
        "Success. Set new primary address.",
        "Success. Added new aliases to user.",
        "Success. Removed specified aliases from user."
      ]
    }
    Error: Returns error details if the operation fails to manage aliases.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $UserObj = $Request.Body
    $TenantFilter = $UserObj.tenantFilter

    if ([string]::IsNullOrWhiteSpace($UserObj.id)) {
        $body = @{'Results' = @('Failed to manage aliases. No user ID provided') }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Body
            })
        return
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    $Aliases = if ($UserObj.AddedAliases) { ($UserObj.AddedAliases -split ',').ForEach({ $_.Trim() }) }
    $RemoveAliases = if ($UserObj.RemovedAliases) { ($UserObj.RemovedAliases -split ',').ForEach({ $_.Trim() }) }

    try {
        if ($Aliases -or $RemoveAliases -or $UserObj.MakePrimary) {
            # Get current mailbox
            $CurrentMailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ Identity = $UserObj.id } -UseSystemMailbox $true

            if (-not $CurrentMailbox) {
                throw 'Could not find mailbox for user'
            }

            $CurrentProxyAddresses = @($CurrentMailbox.EmailAddresses)
            Write-Host "Current proxy addresses: $($CurrentProxyAddresses -join ', ')"
            $NewProxyAddresses = @($CurrentProxyAddresses)

            # Handle setting primary address
            if ($UserObj.MakePrimary) {
                $PrimaryAddress = $UserObj.MakePrimary
                Write-Host "Attempting to set primary address: $PrimaryAddress"

                # Normalize the primary address format
                if ($PrimaryAddress -notlike 'SMTP:*') {
                    $PrimaryAddress = "SMTP:$($PrimaryAddress -replace '^smtp:', '')"
                }
                Write-Host "Normalized primary address: $PrimaryAddress"

                # Check if the address exists in the current addresses (case-insensitive)
                $ExistingAddress = $CurrentProxyAddresses | Where-Object {
                    $current = $_.ToLower()
                    $target = $PrimaryAddress.ToLower()
                    Write-Host "Comparing: '$current' with '$target'"
                    $current -eq $target
                }

                if (-not $ExistingAddress) {
                    Write-Host "Available addresses: $($CurrentProxyAddresses -join ', ')"
                    throw "Cannot set primary address. Address $($PrimaryAddress -replace '^SMTP:', '') not found in user's addresses."
                }

                # Convert all current SMTP addresses to lowercase (secondary)
                $NewProxyAddresses = $NewProxyAddresses | ForEach-Object {
                    if ($_ -like 'SMTP:*') {
                        $_.ToLower()
                    }
                    else {
                        $_
                    }
                }

                # Remove any existing version of the address (case-insensitive)
                $NewProxyAddresses = $NewProxyAddresses | Where-Object {
                    $_.ToLower() -ne $PrimaryAddress.ToLower()
                }
                # Add the new primary address at the beginning
                $NewProxyAddresses = @($PrimaryAddress) + $NewProxyAddresses

                Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Set primary address for $($CurrentMailbox.DisplayName)" -Sev Info
                $Results.Add('Success. Set new primary address.')
            }

            # Remove specified aliases
            if ($RemoveAliases) {
                foreach ($Alias in $RemoveAliases) {
                    # Normalize the alias format
                    if ($Alias -notlike 'smtp:*') {
                        $Alias = "smtp:$Alias"
                    }
                    # Remove the alias case-insensitively
                    $NewProxyAddresses = $NewProxyAddresses | Where-Object {
                        $_.ToLower() -ne $Alias.ToLower()
                    }
                }
                Write-LogMessage -API $ApiName -tenant $TenantFilter -headers $Headers -message "Removed Aliases from $($CurrentMailbox.DisplayName)" -Sev Info
                $Results.Add('Success. Removed specified aliases from user.')
            }

            # Add new aliases
            if ($Aliases) {
                $AliasesToAdd = @()
                foreach ($Alias in $Aliases) {
                    # Normalize the alias format
                    if ($Alias -notlike 'smtp:*') {
                        $Alias = "smtp:$Alias"
                    }
                    # Check if the alias exists case-insensitively
                    if (-not ($NewProxyAddresses | Where-Object { $_.ToLower() -eq $Alias.ToLower() })) {
                        $AliasesToAdd = $AliasesToAdd + $Alias
                    }
                }
                if ($AliasesToAdd.Count -gt 0) {
                    $NewProxyAddresses = $NewProxyAddresses + $AliasesToAdd
                    Write-LogMessage -API $ApiName -tenant ($TenantFilter) -headers $Headers -message "Added Aliases to $($CurrentMailbox.DisplayName)" -Sev Info
                    $Results.Add('Success. Added new aliases to user.')
                }
            }

            # Update the mailbox with new proxy addresses
            $Params = @{
                Identity       = $UserObj.id
                EmailAddresses = $NewProxyAddresses
            }
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams $Params -UseSystemMailbox $true
        }
        else {
            $Results.Add('No alias changes specified.')
        }
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $ApiName -tenant ($TenantFilter) -headers $Headers -message "Alias management failed. $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Results.Add("Failed to manage aliases: $($ErrorMessage.NormalizedError)")
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = @($Results) }
        })
}
