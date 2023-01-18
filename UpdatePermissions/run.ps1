# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

$Table = Get-CIPPTable -TableName cpvtenants
$Rows = Get-AzDataTableEntity @Table

$Tenants = get-tenants

foreach ($Row in $Tenants ) {
    Write-Host "Processing tenants"
    if (!($rows | Where-Object { $_.customerId -NotIn $row.customerId })) {
        Write-Host "Not in list"
        Push-OutputBinding -Name Msg -Value $row.customerId
    }
    if ($rows | Where-Object { $_.customerId -eq $row.customerId -and $_.LastApply -EQ $null -or $_.LastApply -LT (Get-Date).AddDays(-14) }) {
        Write-Host "In list, Old age."
        Push-OutputBinding -Name Msg -Value $row.customerId
    }
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"
