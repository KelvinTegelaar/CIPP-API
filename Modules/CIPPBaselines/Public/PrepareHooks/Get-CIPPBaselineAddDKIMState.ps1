function Get-CIPPBaselineAddDKIMState {
    <#
    .SYNOPSIS
        Prepare hook for AddDKIM: accepted domains without enabled DKIM signing.
    .DESCRIPTION
        Grades which accepted domains have no DKIM config at all plus which have one that is
        disabled - the two lists the classic remediated differently (New- vs Set-), which is
        why both are carried separately for the executor.

        The exclusion list is the classic's, shared with the domain analyser: service
        domains (onmicrosoft, signature services, Teams SBCs) never get DKIM through
        Exchange and would otherwise be permanent false drift.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Domains = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains')
    $DkimConfigs = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoDkimSigningConfig')
    if ($Domains.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains')) {
        return @{ Current = $null }
    }

    $Exclusions = @('*.microsoftonline.com', '*.mail.onmicrosoft.com', '*.exclaimer.cloud', '*.excl.cloud', '*.codetwo.online',
        '*.call2teams.com', '*.signature365.net', '*.myteamsconnect.io', '*.teams.dstny.com', '*.msteams.8x8.com',
        '*.ucconnect.co.uk', '*.teams-sbc.dk')
    $IsExcluded = { param($Name) foreach ($Pattern in $Exclusions) { if ($Name -like $Pattern) { return $true } } $false }

    $AllDomains = @($Domains | ForEach-Object { "$($_.DomainName)" } | Where-Object { $_ -and -not (& $IsExcluded $_) })
    $Dkim = @($DkimConfigs | Where-Object { "$($_.Domain)" -and -not (& $IsExcluded "$($_.Domain)") })

    $NewDomains = @($AllDomains | Where-Object { @($Dkim.Domain) -notcontains $_ } | Sort-Object)
    $SetDomains = @($Dkim | Where-Object { $AllDomains -contains "$($_.Domain)" -and $_.Enabled -eq $false } | ForEach-Object { "$($_.Domain)" } | Sort-Object)

    $Current = [PSCustomObject]@{ domainsWithoutDkim = @(@($NewDomains) + @($SetDomains) | Sort-Object) }
    # Carried for the executor: absent configs are New-ed, disabled ones are Set-.
    $Current | Add-Member -NotePropertyName 'domainsToCreate' -NotePropertyValue @($NewDomains)
    $Current | Add-Member -NotePropertyName 'domainsToEnable' -NotePropertyValue @($SetDomains)

    @{
        Expected = [PSCustomObject]@{ domainsWithoutDkim = @() }
        Current  = $Current
    }
}
