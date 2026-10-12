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

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $Domains = @((Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains').DomainName | Where-Object { $_ })
    if ($Domains.Count -eq 0) { return @{ Current = $null } }

    $Missing = [System.Collections.Generic.List[object]]::new()
    foreach ($Mailbox in $Mailboxes) {
        $UPN = "$($Mailbox.UPN)"
        if ([string]::IsNullOrWhiteSpace($UPN)) { continue }
        $Addresses = @("$($Mailbox.primarySmtpAddress)")
        if (-not [string]::IsNullOrWhiteSpace($Mailbox.AdditionalEmailAddresses)) {
            $Addresses += @("$($Mailbox.AdditionalEmailAddresses)" -split ',\s*')
        }
        $LocalPart = ($UPN -split '@') | Select-Object -First 1
        foreach ($Domain in $Domains) {
            if (@($Addresses | Where-Object { $_ -like "*@$Domain" }).Count -gt 0) { continue }
            $Missing.Add([PSCustomObject]@{ id = $UPN; alias = "smtp:$LocalPart@$Domain"; display = "$UPN -> $Domain" })
        }
    }

    @{
        Current = [PSCustomObject]@{
            offenders = @($Missing.display | Sort-Object)
            targets   = @($Missing | ForEach-Object { [PSCustomObject]@{ id = $_.id; alias = $_.alias } })
        }
    }
}
