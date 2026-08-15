function Get-CIPPBaselineLegacyEmailReportAddinsState {
    <#
    .SYNOPSIS
        Prepare hook for LegacyEmailReportAddins: app registrations carrying a retired Report
        Message or Report Phishing add-in.
    .DESCRIPTION
        Compliance here is ABSENCE, which a declarative read cannot express: a filter that
        matches nothing yields a null Current, and the engine reads that as 'not collected'
        rather than 'clean'. Returning an empty offender list against an empty expected list
        is the honest way to say the tenant has none.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Apps = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Apps' | Where-Object { $_ })
    if ($Apps.Count -eq 0) { return @{ Current = $null } }

    $Legacy = @{
        '3f32746a-0586-4c54-b8ce-d3b611c5b6c8' = 'Report Phishing'
        '6046742c-3aee-485e-a4ac-92ab7199db2e' = 'Report Message'
    }

    $Installed = @($Apps | Where-Object {
            @($_.addIns | Where-Object { $Legacy.ContainsKey("$($_.id)") }).Count -gt 0
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Installed | ForEach-Object {
                    $App = $_
                    @($App.addIns | Where-Object { $Legacy.ContainsKey("$($_.id)") } | ForEach-Object { $Legacy["$($_.id)"] })
                } | Sort-Object -Unique)
            targets   = @($Installed | ForEach-Object { [PSCustomObject]@{ id = "$($_.id)" } })
        }
    }
}
