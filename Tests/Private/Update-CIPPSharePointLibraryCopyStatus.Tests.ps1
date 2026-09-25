# Pester tests for Update-CIPPSharePointLibraryCopyStatus

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $UpdatePath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Update-CIPPSharePointLibraryCopyStatus.ps1'
    if (-not (Test-Path $UpdatePath)) { throw "Could not locate $UpdatePath" }

    function Set-CIPPSharePointLibraryCopyOperation { param([string]$TenantFilter, [string]$OperationId, [hashtable]$Entity) }
    function Get-CIPPSharePointLibraryCopyOperation { param([string]$TenantFilter, [string]$OperationId) }
    function Get-CIPPSharePointCopyJobProgress { param([string]$TenantFilter, [string]$SourceSiteUrl, $CopyJobInfo) }

    . $UpdatePath
}

Describe 'Update-CIPPSharePointLibraryCopyStatus' {
    BeforeEach {
        $script:ProgressCalls = 0

        Mock Get-CIPPSharePointLibraryCopyOperation {
            [PSCustomObject]@{
                OperationId       = $OperationId
                SourceSiteUrl     = 'https://contoso.sharepoint.com/sites/a'
                SourceSiteName    = 'Site A'
                SourceLibraryName = 'Docs'
                DestSiteName      = 'Site B'
                DestLibraryName   = 'Archive'
                StartedBy         = 'admin'
                Status            = 'Processing'
                JobHandleCount    = 1
                Expiry            = ([DateTime]::UtcNow.AddDays(7)).ToString('o')
                CopyJobInfos      = @([PSCustomObject]@{ JobId = 'job-1'; JobQueueUri = 'https://queue'; EncryptionKey = 'key' })
                HandleStates      = @([PSCustomObject]@{ Status = 'Queued'; IsComplete = $false })
                SanitizedSnapshot = $null
            }
        }

        Mock Get-CIPPSharePointCopyJobProgress {
            $script:ProgressCalls++
            [PSCustomObject]@{
                Status               = 'Processing'
                IsComplete           = $false
                ObjectsProcessed     = 1
                TotalExpectedObjects = 5
                FilesCreated         = 0
                BytesProcessed       = 0
                TotalErrors          = 0
                TotalWarnings        = 0
                ErrorMessages        = @()
                WarningMessages      = @()
            }
        }
    }

    It 'polls unfinished handles once per request' {
        $null = Update-CIPPSharePointLibraryCopyStatus -TenantFilter 'contoso.com' -OperationId ([guid]::NewGuid().Guid)

        $script:ProgressCalls | Should -Be 1
    }

    It 'skips already-complete handles' {
        Mock Get-CIPPSharePointLibraryCopyOperation {
            [PSCustomObject]@{
                OperationId       = $OperationId
                SourceSiteUrl     = 'https://contoso.sharepoint.com/sites/a'
                SourceSiteName    = 'Site A'
                SourceLibraryName = 'Docs'
                DestSiteName      = 'Site B'
                DestLibraryName   = 'Archive'
                StartedBy         = 'admin'
                Status            = 'Processing'
                JobHandleCount    = 2
                Expiry            = ([DateTime]::UtcNow.AddDays(7)).ToString('o')
                CopyJobInfos      = @(
                    [PSCustomObject]@{ JobId = 'job-1'; JobQueueUri = 'https://queue'; EncryptionKey = 'key' }
                    [PSCustomObject]@{ JobId = 'job-2'; JobQueueUri = 'https://queue'; EncryptionKey = 'key' }
                )
                HandleStates      = @(
                    [PSCustomObject]@{ Status = 'Complete'; IsComplete = $true; TotalErrors = 0 }
                    [PSCustomObject]@{ Status = 'Queued'; IsComplete = $false }
                )
                SanitizedSnapshot = $null
            }
        }

        $null = Update-CIPPSharePointLibraryCopyStatus -TenantFilter 'contoso.com' -OperationId ([guid]::NewGuid().Guid)

        $script:ProgressCalls | Should -Be 1
    }

    It 'returns cached snapshot for terminal operations without live polling' {
        Mock Get-CIPPSharePointLibraryCopyOperation {
            [PSCustomObject]@{
                Status            = 'Completed'
                HandleStates      = @()
                SanitizedSnapshot = [PSCustomObject]@{
                    OperationId  = 'done-op'
                    Status       = 'Completed'
                    JobsComplete = 1
                    JobsTotal    = 1
                    TotalErrors  = 0
                    Message      = 'Library copy completed.'
                }
            }
        }

        $Result = Update-CIPPSharePointLibraryCopyStatus -TenantFilter 'contoso.com' -OperationId 'done-op'

        $Result.Status | Should -Be 'Completed'
        $script:ProgressCalls | Should -Be 0
    }

    It 'omits DestFolderName from the snapshot and record when the copy targeted the library root' {
        Mock Set-CIPPSharePointLibraryCopyOperation {}

        $Result = Update-CIPPSharePointLibraryCopyStatus -TenantFilter 'contoso.com' -OperationId ([guid]::NewGuid().Guid)

        $Result.PSObject.Properties.Name | Should -Not -Contain 'DestFolderName'
        Should -Invoke Set-CIPPSharePointLibraryCopyOperation -Times 1 -Exactly -ParameterFilter {
            -not $Entity.ContainsKey('DestFolderName')
        }
    }

    It 'reports and re-persists DestFolderName when the copy targeted a folder' {
        Mock Get-CIPPSharePointLibraryCopyOperation {
            [PSCustomObject]@{
                OperationId       = $OperationId
                SourceSiteUrl     = 'https://contoso.sharepoint.com/personal/jane_contoso_com'
                SourceSiteName    = 'Jane Doe'
                SourceLibraryName = 'Documents'
                DestSiteName      = 'Archive'
                DestLibraryName   = 'Leavers'
                DestFolderName    = 'Archive - jane@contoso.com'
                StartedBy         = 'admin'
                Status            = 'Processing'
                JobHandleCount    = 1
                Expiry            = ([DateTime]::UtcNow.AddDays(7)).ToString('o')
                CopyJobInfos      = @([PSCustomObject]@{ JobId = 'job-1'; JobQueueUri = 'https://queue'; EncryptionKey = 'key' })
                HandleStates      = @([PSCustomObject]@{ Status = 'Queued'; IsComplete = $false })
                SanitizedSnapshot = $null
            }
        }
        Mock Set-CIPPSharePointLibraryCopyOperation {}

        $Result = Update-CIPPSharePointLibraryCopyStatus -TenantFilter 'contoso.com' -OperationId ([guid]::NewGuid().Guid)

        $Result.DestFolderName | Should -Be 'Archive - jane@contoso.com'
        Should -Invoke Set-CIPPSharePointLibraryCopyOperation -Times 1 -Exactly -ParameterFilter {
            $Entity.DestFolderName -eq 'Archive - jane@contoso.com' -and
            ($Entity.SanitizedSnapshot | ConvertFrom-Json).DestFolderName -eq 'Archive - jane@contoso.com'
        }
    }
}
