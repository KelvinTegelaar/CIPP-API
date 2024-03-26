param($name)
#$Skiplist = (Get-Content ExcludedTenants -ErrorAction SilentlyContinue | ConvertFrom-Csv -Delimiter "|" -Header "name", "date", "user").name
$Tenants = Get-Tenants #Get-Content ".\tenants.cache.json" | ConvertFrom-Json | Where-Object {$Skiplist -notcontains $_.defaultDomainName}

$object = foreach ($Tenant in $Tenants) {
    $Tenant.defaultDomainName
}
Write-LogMessage -API 'BestPracticeAnalyser' -tenant 'None' -message "running BPA for $($tenants.count) tenants" -sev info

$object