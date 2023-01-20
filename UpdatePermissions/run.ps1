# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

$Table = Get-CIPPTable -TableName cpvtenants
$CPVRows = Get-AzDataTableEntity @Table

$Tenants = get-tenants

foreach ($Row in $Tenants ) {
    Write-Host "Processing tenants"
    if (!($CPVRows)) {
        "No list available"
        Push-OutputBinding -Name Msg -Value $row.customerId
    }

    if (!($CPVRows | Where-Object { $row.customerId -In $CPVRows.Tenant })) {
        "Not in the list: $($row.customerId)"
        Push-OutputBinding -Name Msg -Value $row.customerId
    }

    if ($CPVRows | Where-Object { $_.Tenant -eq $row.customerId } | Where-Object { $_.LastApply -EQ $null -or $_.LastApply -lt (Get-Date).AddDays(-14) }) {
        Write-Host "In list, Old age."
        Push-OutputBinding -Name Msg -Value $row.customerId
    }
}
