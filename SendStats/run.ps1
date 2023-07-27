# Input bindings are passed in via param block.
param($Timer)

#These stats are sent to a central server to help us understand how many tenants are using the product, and how many are using the latest version, this information allows the CIPP team to make decisions about what features to support, and what features to deprecate.
#We will never ship any data that is related to your instance, all we care about is the number of tenants, and the version of the API you are running, and if you completed setup.

if ($ENV:applicationid -ne "LongApplicationID") {
    $SetupComplete = $true
}
$TenantCount = (Get-Tenants).count

Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$APIVersion = Get-Content "version_latest.txt" | Out-String

$SendingObject = [PSCustomObject]@{
    rgid                = $env:WEBSITE_SITE_NAME
    SetupComplete       = $SetupComplete
    RunningVersionAPI   = $APIVersion.trim()
    CountOfTotalTenants = $tenantcount
} | ConvertTo-Json

Invoke-RestMethod -Uri 'https://management.cipp.app/api/stats' -Method POST -Body $SendingObject -ContentType 'application/json'