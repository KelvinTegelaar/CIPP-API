function Get-CIPPBaselineAutoAddProxyState {
    <#
    .SYNOPSIS
        Prepare hook for AutoAddProxy: mailboxes missing a proxy address for an accepted
        domain.
    .DESCRIPTION
        A cross product, which no declarative read can express: every mailbox is checked
        against every accepted domain, and one mailbox can be missing several. Each missing
        (mailbox, domain) pair becomes its own target, so the sweep issues one Set-Mailbox per
        pair exactly as the classic standard did.

        ExoAcceptedDomains is the second cache and goes through Get-CIPPBaselineCacheRows;
        Mailboxes is the declared one and the engine collects it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' -Fields 'UPN', 'primarySmtpAddress', 'AdditionalEmailAddresses' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $Domains = @((Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains').DomainName | Where-Object { $_ })
    if ($Domains.Count -eq 0) { return @{ Current = $null } }

    $Missing = [System.Collections.Generic.List[object]]::new()
    foreach ($Mailbox in $Mailboxes) {
        $UPN = "$($Mailbox.UPN)"
        if ([string]::IsNullOrWhiteSpace($UPN)) { continue }
        $Addresses = @("$($Mailbox.primarySmtpAddress)"; if (-not [string]::IsNullOrWhiteSpace($Mailbox.AdditionalEmailAddresses)) { "$($Mailbox.AdditionalEmailAddresses)" -split ',\s*' })
        $HasDomain = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Address in $Addresses) {
            $At = $Address.LastIndexOf('@')
            if ($At -ge 0) { $null = $HasDomain.Add($Address.Substring($At + 1)) }
        }
        $LocalPart = ($UPN -split '@')[0]
        foreach ($Domain in $Domains) {
            if ($HasDomain.Contains($Domain)) { continue }
            $Missing.Add([PSCustomObject]@{ id = $UPN; alias = "smtp:$LocalPart@$Domain"; display = "$UPN -> $Domain" })
        }
    }

    @{
        Current = [PSCustomObject]@{
            offenders = @($Missing.display | Sort-Object)
            targets   = @(foreach ($Entry in $Missing) { [PSCustomObject]@{ id = $Entry.id; alias = $Entry.alias } })
        }
    }
}
