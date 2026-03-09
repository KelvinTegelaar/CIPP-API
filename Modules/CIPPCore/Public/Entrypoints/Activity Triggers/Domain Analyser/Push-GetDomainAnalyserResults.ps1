function Push-GetDomainAnalyserResults {
    [CmdletBinding()]
    param (
        $Item
    )

    $Tenant = $Item.Parameters.Tenant
    $Results = if ($Item.Results -is [array]) { $Item.Results } else { @($Item.Results) }
    $DomainCount = $Results | Measure-Object | Select-Object -ExpandProperty Count

    # Create summary for logging
    $Summary = [system.collections.generic.list[object]]::new()
    $Results | ForEach-Object {
        $Summary.Add([PSCustomObject]@{
                Domain     = $_.Domain
                Score      = "$($_.Score)/$($_.MaximumScore)"
                Percentage = "$($_.ScorePercentage)%"
            }
        )
    }

    $Message = "Domain Analyser completed for $DomainCount domain(s) in tenant $($Tenant.defaultDomainName)"
    Write-LogMessage -API 'DomainAnalyser' -Tenant $Tenant.defaultDomainName -TenantId $Tenant.customerId -message $Message -sev Info -LogData $Summary

    return
}
