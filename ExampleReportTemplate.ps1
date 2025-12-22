$Table = Get-CippTable -tablename 'CippReportTemplates'

$Entity = @{
    RowKey       = (New-Guid).ToString()
    PartitionKey = 'ReportingTemplate'
    Tests        = [string](@('Test01', 'Test02', 'Test03', 'Test04', 'Test05') | ConvertTo-Json -Compress)
    Description  = 'This is a test report'
    Name         = 'Test Report'
}

Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

Write-Host "Report template created successfully with ID: $($Entity.RowKey)"
