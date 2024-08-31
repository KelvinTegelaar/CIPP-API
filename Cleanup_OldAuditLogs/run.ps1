# Input bindings are passed in via param block.
param($Timer)

try {
    $Tenants = Get-Tenants -IncludeAll | Where-Object { $_.customerId -ne $env:TenantID -and $_.Excluded -eq $false }
    $Tenants | ForEach-Object {
        Remove-CIPPGraphSubscription -cleanup $true -TenantFilter $_.defaultDomainName
    }
} catch {}
