function Disable-CIPPInboxRules {
    <#
    .SYNOPSIS
        Disables a mailbox's inbox rules for BEC containment.
    .DESCRIPTION
        Disables every inbox rule on the mailbox except the Junk E-Mail and out-of-office system rules,
        or only the rules whose Identity is in RuleIds. Each rule is handled on its own: one failure
        never stops the rest, and the Exchange-managed 'Delegate Rule -N' rules, which cannot be
        disabled, are skipped rather than reported as failures. Returns one result row per outcome.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The mailbox.
    .PARAMETER RuleIds
        Optional rule identities to restrict the operation to.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [string[]]$RuleIds,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Results = [System.Collections.Generic.List[object]]::new()
    $Add = { param($Text, $State) $Results.Add([pscustomobject]@{ resultText = $Text; state = $State }) }

    $Rules = @(New-ExoRequest -anchor $UserPrincipalName -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{ Mailbox = $UserPrincipalName; IncludeHidden = $true } | Where-Object { $_ })
    if ($Rules.Count -eq 0) {
        & $Add "No inbox rules found for $UserPrincipalName." 'info'
        return $Results.ToArray()
    }

    $Processable = @($Rules | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' })
    if ($RuleIds) {
        $Processable = @($Processable | Where-Object { $_.Identity -in $RuleIds -or $_.Name -in $RuleIds -or $_.RuleIdentity -in $RuleIds })
    }
    if ($Processable.Count -eq 0) {
        & $Add "Found $($Rules.Count) inbox rule(s) for $UserPrincipalName, but none require disabling (only system rules found)." 'info'
        return $Results.ToArray()
    }

    $Disabled = 0
    $Skipped = 0
    foreach ($Rule in $Processable) {
        if (-not $PSCmdlet.ShouldProcess("$UserPrincipalName rule '$($Rule.Name)'", 'Disable inbox rule')) { continue }
        try {
            $null = Set-CIPPMailboxRule -Username $UserPrincipalName -UserId $UserPrincipalName -TenantFilter $TenantFilter -RuleId $Rule.Identity -RuleName $Rule.Name -Disable -APIName $APIName -Headers $Headers
            $Disabled++
        } catch {
            if ($Rule.Name -match '^Delegate Rule -\d+$') {
                # Exchange-managed delegate rules cannot be disabled; expected, not a failure.
                $Skipped++
            } else {
                & $Add "Could not disable rule '$($Rule.Name)': $($_.Exception.Message)" 'error'
            }
        }
    }
    if ($Disabled -gt 0) { & $Add "Disabled $Disabled inbox rule(s) for $UserPrincipalName." 'success' }
    if ($Skipped -gt 0) { & $Add "Skipped $Skipped Exchange-managed delegate rule(s) that cannot be disabled." 'info' }
    if ($Disabled -eq 0 -and $Skipped -eq 0 -and $Results.Count -eq 0) { & $Add "No processable inbox rules found for $UserPrincipalName." 'info' }
    return $Results.ToArray()
}
