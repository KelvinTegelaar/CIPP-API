# Pester tests for Get-CIPPSharePointCopyJobProgress sanitization

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSharePointCopyJobProgress.ps1'
    $QueuePath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSharePointCopyJobQueueLogs.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }
    if (-not (Test-Path $QueuePath)) { throw "Could not locate $QueuePath" }

    function Get-SharePointAdminLink { param($Public, $tenantFilter) [PSCustomObject]@{ SharePointUrl = 'https://contoso.sharepoint.com' } }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body) }

    . $QueuePath
    . $FunctionPath
}

Describe 'Get-CIPPSharePointCopyJobProgress' {
    It 'aggregates errors without returning raw log paths' {
        Mock New-GraphPOSTRequest {
            [PSCustomObject]@{
                d = [PSCustomObject]@{
                    GetCopyJobProgress = [PSCustomObject]@{
                        JobState = 0
                        Logs     = @(
                            '{"Event":"JobError","Url":"/sites/x/secret/file.docx","Message":"failed"}'
                            '{"Event":"JobProgress","ObjectsProcessed":10,"TotalExpectedSPObjects":20,"TotalErrors":1}'
                        )
                    }
                }
            }
        }
        Mock Get-CIPPSharePointCopyJobQueueLogs { @() }

        $Result = Get-CIPPSharePointCopyJobProgress -TenantFilter 'contoso.com' -SourceSiteUrl 'https://contoso.sharepoint.com/sites/a' -CopyJobInfo @{
            JobId = 'job-1'; JobQueueUri = 'https://queue'; EncryptionKey = 'key'
        }

        $Result.TotalErrors | Should -BeGreaterThan 0
        $Result.ErrorMessages.Count | Should -BeGreaterThan 0
        $Result | Get-Member -Name Url | Should -BeNullOrEmpty
        ($Result | ConvertTo-Json) | Should -Not -Match 'secret/file'
        ($Result.ErrorMessages -join ' ') | Should -Not -Match 'secret/file'
    }

    It 'reads OData verbose Logs.results and Event-based job errors' {
        Mock New-GraphPOSTRequest {
            [PSCustomObject]@{
                d = [PSCustomObject]@{
                    GetCopyJobProgress = [PSCustomObject]@{
                        JobState = 0
                        Logs     = [PSCustomObject]@{
                            results = @(
                                '{"Event":"JobEnd","TotalErrors":1}'
                                '{"Event":"JobError","ObjectType":"File","ErrorType":"Microsoft.SharePoint.SPException","ErrorCode":"-2147024816","Message":"Access denied."}'
                            )
                        }
                    }
                }
            }
        }
        Mock Get-CIPPSharePointCopyJobQueueLogs { @() }

        $Result = Get-CIPPSharePointCopyJobProgress -TenantFilter 'contoso.com' -SourceSiteUrl 'https://contoso.sharepoint.com/sites/a' -CopyJobInfo @{
            JobId = 'job-2'; JobQueueUri = 'https://queue'; EncryptionKey = 'key'
        }

        $Result.TotalErrors | Should -BeGreaterThan 0
        ($Result.ErrorMessages -join ' ') | Should -Match 'Access denied'
        ($Result.ErrorMessages -join ' ') | Should -Match 'File'
    }

    It 'falls back to Azure queue logs when REST logs omit JobError detail' {
        Mock New-GraphPOSTRequest {
            [PSCustomObject]@{
                d = [PSCustomObject]@{
                    GetCopyJobProgress = [PSCustomObject]@{
                        JobState = 0
                        Logs     = @('{"Event":"JobEnd","TotalErrors":1}')
                    }
                }
            }
        }
        Mock Get-CIPPSharePointCopyJobQueueLogs {
            @([PSCustomObject]@{
                    Event      = 'JobError'
                    ObjectType = 'File'
                    Message    = 'Access denied.'
                    ErrorCode  = '-2147024816'
                })
        }

        $Result = Get-CIPPSharePointCopyJobProgress -TenantFilter 'contoso.com' -SourceSiteUrl 'https://contoso.sharepoint.com/sites/a' -CopyJobInfo @{
            JobId = 'job-3'; JobQueueUri = 'https://queue.example/messages?sas=1'; EncryptionKey = 'key'
        }

        ($Result.ErrorMessages -join ' ') | Should -Match 'Access denied'
    }

    It 'sanitizes path-like content from error messages' {
        Mock New-GraphPOSTRequest {
            [PSCustomObject]@{
                d = [PSCustomObject]@{
                    GetCopyJobProgress = [PSCustomObject]@{
                        JobState = 0
                        Logs     = @(
                            '{"Event":"JobError","Message":"Could not copy /sites/hr/Shared Documents/report.docx because access denied"}'
                        )
                    }
                }
            }
        }
        Mock Get-CIPPSharePointCopyJobQueueLogs { @() }

        $Result = Get-CIPPSharePointCopyJobProgress -TenantFilter 'contoso.com' -SourceSiteUrl 'https://contoso.sharepoint.com/sites/a' -CopyJobInfo @{
            JobId = 'job-sanitize'; JobQueueUri = 'https://queue'; EncryptionKey = 'key'
        }

        ($Result.ErrorMessages -join ' ') | Should -Not -Match 'Shared Documents'
        ($Result.ErrorMessages -join ' ') | Should -Not -Match 'report\.docx'
        ($Result.ErrorMessages -join ' ') | Should -Match 'access denied'
    }

    It 'sends copyJobInfo wrapper in GetCopyJobProgress POST body' {
        $script:CapturedBody = $null
        Mock New-GraphPOSTRequest {
            param($body)
            $script:CapturedBody = $body
            [PSCustomObject]@{
                d = [PSCustomObject]@{
                    GetCopyJobProgress = [PSCustomObject]@{
                        JobState = 0
                        Logs     = @()
                    }
                }
            }
        }
        Mock Get-CIPPSharePointCopyJobQueueLogs { @() }

        $null = Get-CIPPSharePointCopyJobProgress -TenantFilter 'contoso.com' -SourceSiteUrl 'https://contoso.sharepoint.com/sites/a' -CopyJobInfo @{
            JobId = 'job-body'; JobQueueUri = 'https://queue'; EncryptionKey = 'key'
        }

        $ParsedBody = $script:CapturedBody | ConvertFrom-Json
        $ParsedBody.copyJobInfo.JobId | Should -Be 'job-body'
        $ParsedBody.copyJobInfo.JobQueueUri | Should -Be 'https://queue'
        $ParsedBody.copyJobInfo.EncryptionKey | Should -Be 'key'
        $ParsedBody.copyJobInfo.__metadata.type | Should -Be 'SP.CopyMigrationInfo'
    }

    It 'unwraps OData collection wrappers stored as CopyJobInfo' {
        $script:CapturedBody = $null
        Mock New-GraphPOSTRequest {
            param($body)
            $script:CapturedBody = $body
            [PSCustomObject]@{
                d = [PSCustomObject]@{
                    GetCopyJobProgress = [PSCustomObject]@{
                        JobState = 0
                        Logs     = @('{"Event":"JobEnd","TotalErrors":0}')
                    }
                }
            }
        }
        Mock Get-CIPPSharePointCopyJobQueueLogs { @() }

        $Result = Get-CIPPSharePointCopyJobProgress -TenantFilter 'contoso.com' -SourceSiteUrl 'https://contoso.sharepoint.com/sites/a' -CopyJobInfo ([PSCustomObject]@{
                __metadata = [PSCustomObject]@{ type = 'Collection(SP.CopyMigrationInfo)' }
                results    = @(
                    [PSCustomObject]@{
                        JobId         = 'job-from-results'
                        JobQueueUri   = 'https://queue/messages'
                        EncryptionKey = 'key'
                    }
                )
            })

        $ParsedBody = $script:CapturedBody | ConvertFrom-Json
        $ParsedBody.copyJobInfo.JobId | Should -Be 'job-from-results'
        $Result.IsComplete | Should -Be $true
    }

    It 'uses queue logs when GetCopyJobProgress REST fails' {
        Mock New-GraphPOSTRequest { throw 'REST unavailable' }
        Mock Get-CIPPSharePointCopyJobQueueLogs {
            @([PSCustomObject]@{
                    Event            = 'JobEnd'
                    TotalErrors      = 1
                    ObjectsProcessed = 0
                },
                [PSCustomObject]@{
                    Event      = 'JobError'
                    ObjectType = 'File'
                    Message    = 'Access denied.'
                })
        }

        $Result = Get-CIPPSharePointCopyJobProgress -TenantFilter 'contoso.com' -SourceSiteUrl 'https://contoso.sharepoint.com/sites/a' -CopyJobInfo @{
            JobId = 'job-rest-fail'; JobQueueUri = 'https://queue.example/messages?sas=1'; EncryptionKey = 'key'
        }

        $Result.IsComplete | Should -Be $true
        $Result.TotalErrors | Should -BeGreaterThan 0
        ($Result.ErrorMessages -join ' ') | Should -Match 'Access denied'
    }
}
