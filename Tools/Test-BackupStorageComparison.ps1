param(
    [Parameter(Mandatory = $false)] [string] $ConnectionString = $env:AzureWebJobsStorage,
    [Parameter(Mandatory = $false)] [ValidateSet('Small', 'Medium', 'Large', 'All')] [string] $TestSize = 'All',
    [Parameter(Mandatory = $false)] [bool] $Cleanup = $true
)

$ErrorActionPreference = 'Stop'

# Import CIPPCore module from repository
$modulePath = Join-Path $PSScriptRoot '..' 'Modules' 'CIPPCore' 'CIPPCore.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "CIPPCore module not found at $modulePath"
}
Import-Module -Force $modulePath

if (-not $ConnectionString) {
    throw 'Azure Storage connection string not provided. Set AzureWebJobsStorage or pass -ConnectionString.'
}

Write-Host '================================' -ForegroundColor Cyan
Write-Host 'Backup Storage Comparison Tests' -ForegroundColor Cyan
Write-Host '================================' -ForegroundColor Cyan

# Test data configurations
$testConfigs = @(
    @{
        Name              = 'Small'
        ItemCount         = 10
        PropertiesPerItem = 5
        Description       = 'Small payload (~5KB)'
    },
    @{
        Name              = 'Medium'
        ItemCount         = 100
        PropertiesPerItem = 15
        Description       = 'Medium payload (~250KB)'
    },
    @{
        Name              = 'Large'
        ItemCount         = 500
        PropertiesPerItem = 30
        Description       = 'Large payload (~2.5MB)'
    }
)

function Generate-TestData {
    param(
        [int]$ItemCount,
        [int]$PropertiesPerItem,
        [string]$Type
    )

    $data = @()
    for ($i = 0; $i -lt $ItemCount; $i++) {
        $item = @{
            id        = [guid]::NewGuid().ToString()
            rowKey    = "item_$i"
            timestamp = (Get-Date).ToUniversalTime()
            table     = $Type
        }

        for ($p = 0; $p -lt $PropertiesPerItem; $p++) {
            $item["property_$p"] = "This is test property $p with some additional content to make it realistic. Lorem ipsum dolor sit amet." * 3
        }

        $data += $item
    }

    return $data
}

function Test-TableStorage {
    param(
        [array]$TestData,
        [string]$TestName
    )

    Write-Host "`n[TABLE STORAGE] Testing $TestName..." -ForegroundColor Yellow

    $tableName = "TestBackup$(Get-Random -Maximum 100000)"
    $Table = Get-CippTable -tablename $tableName

    $jsonString = $TestData | ConvertTo-Json -Depth 100 -Compress
    $jsonSizeKB = [math]::Round(($jsonString | Measure-Object -Character).Characters / 1KB, 2)

    Write-Host "  JSON Size: $jsonSizeKB KB"

    # Time the storage operation
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $entity = @{
            PartitionKey = 'TestBackup'
            RowKey       = $TestName
            Backup       = [string]$jsonString
        }
        Add-CIPPAzDataTableEntity @Table -Entity $entity -Force -ErrorAction Stop
        $stopwatch.Stop()

        Write-Host "  Write Time: $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Green
        Write-Host '  Status: Success ✓' -ForegroundColor Green

        return @{
            Method    = 'Table Storage'
            TestName  = $TestName
            Size      = $jsonSizeKB
            WriteTime = $stopwatch.ElapsedMilliseconds
            Success   = $true
            Details   = "Stored in table '$tableName'"
        }
    } catch {
        $stopwatch.Stop()
        Write-Host "  Status: Failed ✗ - $($_.Exception.Message)" -ForegroundColor Red

        return @{
            Method    = 'Table Storage'
            TestName  = $TestName
            Size      = $jsonSizeKB
            WriteTime = $stopwatch.ElapsedMilliseconds
            Success   = $false
            Details   = $_.Exception.Message
        }
    }
}

function Test-BlobStorage {
    param(
        [array]$TestData,
        [string]$TestName
    )

    Write-Host "`n[BLOB STORAGE] Testing $TestName..." -ForegroundColor Yellow

    $containerName = 'test-backup-comparison'
    $blobName = "backup_$TestName`_$(Get-Random -Maximum 100000).json"

    $jsonString = $TestData | ConvertTo-Json -Depth 100 -Compress
    $jsonSizeKB = [math]::Round(($jsonString | Measure-Object -Character).Characters / 1KB, 2)

    Write-Host "  JSON Size: $jsonSizeKB KB"

    try {
        # Ensure container exists
        $containers = @()
        try {
            $containers = New-CIPPAzStorageRequest -Service 'blob' -Component 'list' -ConnectionString $ConnectionString
        } catch { $containers = @() }

        $exists = ($containers | Where-Object { $_.Name -eq $containerName }) -ne $null
        if (-not $exists) {
            Write-Host "  Creating container '$containerName'..." -ForegroundColor Gray
            $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $containerName -Method 'PUT' -QueryParams @{ restype = 'container' } -ConnectionString $ConnectionString
            Start-Sleep -Milliseconds 500
        }

        # Time the upload operation
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = New-CIPPAzStorageRequest -Service 'blob' -Resource "$containerName/$blobName" -Method 'PUT' -ContentType 'application/json; charset=utf-8' -Body $jsonString -ConnectionString $ConnectionString
        $stopwatch.Stop()

        Write-Host "  Write Time: $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Green
        Write-Host '  Status: Success ✓' -ForegroundColor Green
        Write-Host "  Location: $containerName/$blobName" -ForegroundColor Gray

        return @{
            Method    = 'Blob Storage'
            TestName  = $TestName
            Size      = $jsonSizeKB
            WriteTime = $stopwatch.ElapsedMilliseconds
            Success   = $true
            Details   = "$containerName/$blobName"
        }
    } catch {
        $stopwatch.Stop()
        Write-Host "  Status: Failed ✗ - $($_.Exception.Message)" -ForegroundColor Red

        return @{
            Method    = 'Blob Storage'
            TestName  = $TestName
            Size      = $jsonSizeKB
            WriteTime = $stopwatch.ElapsedMilliseconds
            Success   = $false
            Details   = $_.Exception.Message
        }
    }
}

# Run tests
$results = @()
$configsToRun = if ($TestSize -eq 'All') { $testConfigs } else { $testConfigs | Where-Object { $_.Name -eq $TestSize } }

foreach ($config in $configsToRun) {
    Write-Host "`n`n$($config.Description)" -ForegroundColor Magenta
    Write-Host "Generating test data ($($config.ItemCount) items, $($config.PropertiesPerItem) properties)..." -ForegroundColor Gray

    $testData = Generate-TestData -ItemCount $config.ItemCount -PropertiesPerItem $config.PropertiesPerItem -Type "Backup_$($config.Name)"

    # Test table storage
    $tableResult = Test-TableStorage -TestData $testData -TestName $config.Name
    $results += $tableResult

    Start-Sleep -Milliseconds 500

    # Test blob storage
    $blobResult = Test-BlobStorage -TestData $testData -TestName $config.Name
    $results += $blobResult
}

# Summary
Write-Host "`n`n================================" -ForegroundColor Cyan
Write-Host 'Test Summary' -ForegroundColor Cyan
Write-Host '================================' -ForegroundColor Cyan

$results | Group-Object -Property TestName | ForEach-Object {
    $testGroup = $_
    Write-Host "`n$($testGroup.Name):" -ForegroundColor Magenta

    $testGroup.Group | ForEach-Object {
        $status = if ($_.Success) { '✓' } else { '✗' }
        Write-Host "  $($_.Method): $($_.Size)KB | Write: $($_.WriteTime)ms | $status" -ForegroundColor $(if ($_.Success) { 'Green' } else { 'Red' })
    }
}

# Detailed comparison
Write-Host "`n`n================================" -ForegroundColor Cyan
Write-Host 'Performance Comparison' -ForegroundColor Cyan
Write-Host '================================' -ForegroundColor Cyan

$results | Group-Object -Property TestName | ForEach-Object {
    $testGroup = $_
    $tableResult = $testGroup.Group | Where-Object { $_.Method -eq 'Table Storage' }
    $blobResult = $testGroup.Group | Where-Object { $_.Method -eq 'Blob Storage' }

    if ($tableResult -and $blobResult -and $tableResult.Success -and $blobResult.Success) {
        $timeDiff = $blobResult.WriteTime - $tableResult.WriteTime
        $timePercentage = [math]::Round(($timeDiff / $tableResult.WriteTime) * 100, 2)

        Write-Host "`n$($testGroup.Name):" -ForegroundColor Magenta
        Write-Host "  Table Write Time: $($tableResult.WriteTime)ms" -ForegroundColor Gray
        Write-Host "  Blob Write Time:  $($blobResult.WriteTime)ms" -ForegroundColor Gray

        if ($timeDiff -gt 0) {
            Write-Host "  Blob is $($timeDiff)ms slower ($($timePercentage)% slower)" -ForegroundColor Yellow
        } else {
            Write-Host "  Blob is $((-$timeDiff))ms faster ($($(-$timePercentage))% faster)" -ForegroundColor Green
        }
    }
}

Write-Host "`n`nTest Complete!" -ForegroundColor Green
