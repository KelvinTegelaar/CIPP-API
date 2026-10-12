function Get-CIPPBaselineCreateSharedMailboxState {
    <#
    .SYNOPSIS
        Prepare hook for CreateSharedMailbox: does a mailbox with the configured address exist.
    .DESCRIPTION
        One instance grades ONE mailbox. The configured primary SMTP address is matched
        case-insensitively against primarySmtpAddress and UPN in the Mailboxes cache; the
        grade is existence only - an existing mailbox is never diffed, so a mailbox that
        was created by hand (or that is a user mailbox occupying the address) is compliant.
        Recipient type and the Exchange-side account-disabled flag ride along on Current
        for the operator to see, ungraded.

        The Mailboxes cache is the definition's declared type, so an empty read returns a
        null Current and lets the engine collect-on-miss (Types 'None' - never the
        permission/rule fan-out). An Exchange tenant with zero cached mailboxes is a
        collection failure, not an empty tenant, so this hook never claims drift on it.

        Tenant tokens in the address (%defaultdomain%) are resolved by the engine's
        variable pass before this hook runs.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $V = $Item.Variables
    # The identity may arrive as an option object ({label, value}) from some save paths.
    $Address = "$($V.primarySmtpAddress.value ?? $V.primarySmtpAddress)".Trim()
    if ([string]::IsNullOrWhiteSpace($Address)) { return @{ Current = $null } }
    try { $null = [System.Net.Mail.MailAddress]::new($Address) } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "CreateSharedMailbox: '$Address' is not a valid email address and cannot be evaluated." -Sev 'Error'
        return @{ Current = $null; NoDataReason = "the configured address '$Address' is not a valid email address" }
    }

    $Existing = @($Mailboxes | Where-Object {
            "$($_.primarySmtpAddress)".Equals($Address, [System.StringComparison]::OrdinalIgnoreCase) -or
            "$($_.UPN)".Equals($Address, [System.StringComparison]::OrdinalIgnoreCase)
        }) | Select-Object -First 1

    $Current = [PSCustomObject]@{
        exists             = ($null -ne $Existing)
        primarySmtpAddress = $(if ($Existing) { "$($Existing.primarySmtpAddress)" } else { $Address })
    }
    if ($Existing) {
        # Carried for the operator and the executor, not graded.
        $Current | Add-Member -NotePropertyName 'displayName' -NotePropertyValue "$($Existing.displayName)"
        $Current | Add-Member -NotePropertyName 'recipientTypeDetails' -NotePropertyValue "$($Existing.recipientTypeDetails)"
        $Current | Add-Member -NotePropertyName 'accountDisabled' -NotePropertyValue ([bool]$Existing.AccountDisabled)
        $Current | Add-Member -NotePropertyName 'externalDirectoryObjectId' -NotePropertyValue "$($Existing.ExternalDirectoryObjectId)"
    }

    @{
        Expected = [PSCustomObject]@{ exists = $true }
        Current  = $Current
    }
}
