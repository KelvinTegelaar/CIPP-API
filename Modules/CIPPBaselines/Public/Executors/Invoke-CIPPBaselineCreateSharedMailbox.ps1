function Invoke-CIPPBaselineCreateSharedMailbox {
    <#
    .SYNOPSIS
        CreateSharedMailbox executor: creates the shared mailbox and blocks its sign-in.
    .DESCRIPTION
        Three steps, in order: New-Mailbox -Shared with the configured display name and
        primary SMTP address, a three-second wait for the Entra object Exchange provisions
        behind the mailbox to settle, then a Graph PATCH that sets accountEnabled to false
        on that object - the same write the AddSharedMailbox endpoint performs.

        The Mailboxes cache refreshes on its own schedule, never right after a remediation.
        A run that lands between the create and the next collection reads the mailbox as
        missing and would call New-Mailbox again, which fails on a taken address. One live
        Get-Mailbox settles it: an address that already resolves returns Changed=$false and
        the run grades Compliant. An existing mailbox is never modified.

        A failed sign-in block after a successful create is thrown, not swallowed: the row
        shows Error with the reason, instead of a Remediated mailbox whose account is still
        enabled.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    # Values may arrive as option objects ({label, value}) from some save paths.
    $Address = "$($Remediate.primarySmtpAddress.value ?? $Remediate.primarySmtpAddress)".Trim()
    $DisplayName = "$($Remediate.displayName.value ?? $Remediate.displayName)".Trim()
    if ([string]::IsNullOrWhiteSpace($Address) -or [string]::IsNullOrWhiteSpace($DisplayName)) {
        throw 'CreateSharedMailbox needs both a primary email address and a display name.'
    }
    try { $null = [System.Net.Mail.MailAddress]::new($Address) } catch {
        throw "CreateSharedMailbox: '$Address' is not a valid email address."
    }

    $Live = $(try {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ Identity = $Address } -UseSystemMailbox $true | Select-Object -First 1
        } catch { $null })
    if ($Live) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Shared mailbox '$Address' already exists; nothing to create." -Sev 'Info'
        return [PSCustomObject]@{ Changed = $false }
    }

    $NewMailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-Mailbox' -cmdParams @{
        displayName        = $DisplayName
        name               = $Address.Split('@')[0]
        primarySMTPAddress = $Address
        Shared             = $true
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created shared mailbox '$DisplayName' with address $Address." -Sev 'Info'

    # Exchange provisions the directory object asynchronously; patch it too early and Graph
    # reports the user as not found.
    Start-Sleep -Seconds 3

    # A shared mailbox's UPN is its primary address, so Graph resolves the address when the
    # create response carries no object id.
    $UserId = "$($NewMailbox.ExternalDirectoryObjectId)"
    if ([string]::IsNullOrWhiteSpace($UserId)) { $UserId = $Address }
    try {
        $Body = ConvertTo-Json -Compress -InputObject @{ accountEnabled = $false }
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$UserId" -tenantid $TenantFilter -type PATCH -body $Body
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Blocked sign-in for shared mailbox $Address." -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created shared mailbox $Address but failed to block sign-in: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Created shared mailbox '$Address' but failed to block sign-in for its account: $($ErrorMessage.NormalizedError)"
    }
}
