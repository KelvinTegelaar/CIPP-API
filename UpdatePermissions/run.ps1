# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

$Table = Get-CIPPTable -TableName cpvtenants
$Rows = Get-AzDataTableEntity @Table

$Tenants = get-tenants

foreach ($Row in $Tenants ) {
    Write-Host "Processing tenants"
    if (!$rows) {
        Push-OutputBinding -Name Msg -Value $row.customerId
    }

    if ($rows | Where-Object { $_.customerId -eq $row.customerId } | Where-Object { $_.LastApply -EQ $null -or $_.LastApply -lt (Get-Date).AddSeconds(-14) }) {
        Write-Host "In list, Old age."
        Push-OutputBinding -Name Msg -Value $row.customerId
    }
}
