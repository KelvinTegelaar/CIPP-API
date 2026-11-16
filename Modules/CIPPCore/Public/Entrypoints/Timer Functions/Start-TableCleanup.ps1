function Start-TableCleanup {
    <#
    .SYNOPSIS
    Start the Table Cleanup Timer
    #>
    param()

    $FixedCacheTables = @(
        'cacheAccessUserRoles', 'CacheAsyncDeployments', 'cacheauditloglookups', 'CacheAzureServiceTags', 'cachebasicauth',
        'CacheCapabilities', 'cacheCAPolicies', 'CacheDefenderTvmExport', 'CacheExtensionSync', 'cachegeoip',
        'cacheGitHubReleaseNotes', 'CacheGroupCreation', 'cachehttppermissions', 'CacheHuduAssets', 'CacheHuduRelations',
        'CacheJITAdmin', 'cachelicenses', 'CacheM365IPRanges', 'cachemfa', 'CacheMxRecords', 'CacheNinjaOneParsedDevices',
        'CacheNinjaOneParsedUsers', 'CacheNinjaOneUsersUpdate', 'cacheQuarantineMessages', 'cachespotenant',
        'cachetenantskus', 'CacheTransportRules', 'CacheVersions', 'CacheWebhooks'
    )
    try {
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage
        $GraphCacheTables = foreach ($TableName in (Get-AzDataTable -Context $Context)) {
            if ($TableName -match '^cache' -and $TableName -notin $FixedCacheTables) { $TableName }
        }
    } catch {
        Write-Warning "Could not list tables for Graph cache cleanup: $($_.Exception.Message)"
        $GraphCacheTables = @()
    }
    $GraphCacheCutoff = (Get-Date).AddHours(-24).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    $Batch = @(
        # Get-GraphRequestList tables: read for 1 h, rows up to ~1 MB, part rows share the root's age
        foreach ($TableName in $GraphCacheTables) {
            @{
                FunctionName   = 'TableCleanupTask'
                Type           = 'CleanupRule'
                TableName      = $TableName
                RawDelete      = $true
                DataTableProps = @{
                    Filter   = "Timestamp lt datetime'$GraphCacheCutoff'"
                    First    = 1000
                    Property = @('PartitionKey', 'RowKey', 'ETag')
                }
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'webhookTable'
            DataTableProps = @{
                Property = @('PartitionKey', 'RowKey', 'ETag', 'Resource')
                First    = 1000
            }
            Where          = "`$_.Resource -match '^Audit'"
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CippReportingDB'
            DataTableProps = @{
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-30).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'AuditLogSearches'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'Search' and Timestamp lt datetime'$((Get-Date).AddHours(-12).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CippFunctionStats'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'Durable' and Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CippQueue'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'CippQueue' and Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CippQueueTasks'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'Task' and Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'ScheduledTasks'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'ScheduledTask' and Command eq 'Sync-CippExtensionData'"
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CippStandardsReports'
            DataTableProps = @{
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'cacheQuarantineMessages'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'QuarantineMessage' and Timestamp lt datetime'$((Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'BecRunState'
            DataTableProps = @{
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-2).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CippOrchestratorBatch'
            DataTableProps = @{
                Filter   = "Timestamp lt datetime'$((Get-Date).AddHours(-24).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'knownlocationdbv2'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'ip' and Timestamp lt datetime'$((Get-Date).AddDays(-90).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            # Baseline run/audit history: 90-day rolling retention. Active tenant-standard
            # pairs rewrite rows every 12h run, so recent history always survives; pairs
            # that stopped resolving age out entirely with their rows.
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'BaselineHistory'
            DataTableProps = @{
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-90).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            # Live-progress rows of background jobs (SharePoint template deploys, user offboarding).
            # They matter while the job runs; a month covers looking back at a task page afterwards.
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CacheAsyncDeployments'
            DataTableProps = @{
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-30).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            # 5-minute instance health samples and boot markers. Two weeks covers the
            # diagnostics window (max 14 days) with nothing left over.
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'InstanceHealth'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'InstanceHealth' and Timestamp lt datetime'$((Get-Date).AddDays(-14).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            # Scripted alert run history, one partition per UTC day. The range leaves the 'LastRun' markers alone.
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'AlertRunHistory'
            DataTableProps = @{
                Filter   = "PartitionKey lt '$((Get-Date).AddDays(-30).ToUniversalTime().ToString('yyyyMMdd'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            # Audit records processing never drained, including pre-partition tenant rows.
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CacheWebhooks'
            DataTableProps = @{
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName = 'TableCleanupTask'
            Type         = 'DeleteTable'
            Tables       = @('knownlocationdb', 'CacheExtensionSync', 'ExtensionSync', 'cachebpav2', 'CacheWebhookStats', 'FailedAuditLogDownloads', 'cachealertsandincidents', 'cachembxrules')
        }
    )

    $InputObject = @{
        Batch            = @($Batch)
        OrchestratorName = 'TableCleanup'
        AllowCollision   = $false
        Priority         = 8
        SkipLog          = $true
    }

    Start-CIPPOrchestrator -InputObject $InputObject
}
