function Push-GetDomainAnalyserResults {
    [CmdletBinding()]
    param (
        $Item
    )

    $Tenant = $Item.Parameters.Tenant
    Write-LogMessage -API 'DomainAnalyser' -Tenant $Tenant.defaultDomainName -TenantId $Tenant.customerId -message "Domain Analyser completed for tenant $($Tenant.defaultDomainName)" -sev Info -LogData ($Item.Results | Select-Object Domain, @{Name = 'Score'; Expression = { "$($_.Score)/$($_.MaximumScore)" } })
    return
}
