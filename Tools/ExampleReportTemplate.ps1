$Table = Get-CippTable -tablename 'CippReportTemplates'

# Dynamically discover all ZTNA test files
$TestFiles = Get-ChildItem "C:\Github\CIPP-API\Modules\CIPPCore\Public\Tests\Invoke-CippTestZTNA*.ps1" | Sort-Object Name
$AllTestIds = $TestFiles.BaseName | ForEach-Object { $_ -replace 'Invoke-CippTestZTNA', 'ZTNA' }

Write-Host "Discovered $($AllTestIds.Count) ZTNA tests"

$Entity = @{
    RowKey        = 'd5d1e123-bce0-482d-971f-be6ed820dd92'
    PartitionKey  = 'ReportingTemplate'
    IdentityTests = [string]($AllTestIds | ConvertTo-Json -Compress)
    Description   = 'Complete Zero Trust Network Assessment Report'
    Name          = 'Full ZTNA Report'
}

Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

Write-Host "Report template created successfully with ID: $($Entity.RowKey)"
