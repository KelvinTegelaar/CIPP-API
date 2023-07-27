# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

$Table = Get-CIPPTable -TableName cpvtenants
$CPVRows = Get-AzDataTableEntity @Table

$Tenants = get-tenants
$TenantList = $CPVRows.Tenant
foreach ($Row in $Tenants ) {
    Write-Output "Processing tenants"

    if (!$CPVRows) {
        Write-Output "No list available"
        Push-OutputBinding -Name Msg -Value $row.customerId
        continue
    }

    if ($Row.customerId -notin $TenantList) {
        Write-Output "Not in the list: $($row.customerId)"
        Push-OutputBinding -Name Msg -Value $row.customerId
        continue

    }

    if ($CPVRows | Where-Object { $_.Tenant -eq $row.customerId } | Where-Object { $_.LastApply -EQ $null -or (Get-Date $_.LastApply).AddDays(-14) -gt $currentUTCtime }) {
        Write-Output "In list, Old age."
        Push-OutputBinding -Name Msg -Value $row.customerId
        continue
    }
}