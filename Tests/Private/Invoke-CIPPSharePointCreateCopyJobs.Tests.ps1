# Pester tests for Invoke-CIPPSharePointCreateCopyJobs OData verbose handle parsing

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPSharePointCreateCopyJobs.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }

    function Get-SharePointAdminLink { param($Public, $tenantFilter) [PSCustomObject]@{ SharePointUrl = 'https://contoso.sharepoint.com' } }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $contentType) }

    . $FunctionPath
}

Describe 'Invoke-CIPPSharePointCreateCopyJobs' {
    It 'unwraps OData verbose CreateCopyJobs.results into normalized handles' {
        Mock New-GraphPOSTRequest {
            [PSCustomObject]@{
                d = [PSCustomObject]@{
                    CreateCopyJobs = [PSCustomObject]@{
                        __metadata = [PSCustomObject]@{ type = 'Collection(SP.CopyMigrationInfo)' }
                        results    = @(
                            [PSCustomObject]@{
                                EncryptionKey           = 'abc123base64='
                                JobId                   = 'd0a42793-f995-4ce2-b0fb-cc3c0e819e19'
                                JobQueueUri             = 'https://queue.core.windows.net/job?sv=1&sig=x'
                                SourceListItemUniqueIds = [PSCustomObject]@{
                                    results = @('208875e4-2659-433d-acd8-4d77fc76e1ef')
                                }
                            }
                        )
                    }
                }
            }
        }

        $Result = Invoke-CIPPSharePointCreateCopyJobs -TenantFilter 'contoso.com' `
            -SourceSiteUrl 'https://contoso.sharepoint.com/sites/a' `
            -ExportObjectUris @('https://contoso.sharepoint.com/sites/a/Shared%20Documents/Folder') `
            -DestinationUri 'https://contoso.sharepoint.com/sites/b/Shared%20Documents'

        $Result.Count | Should -Be 1
        $Result[0].JobId | Should -Be 'd0a42793-f995-4ce2-b0fb-cc3c0e819e19'
        $Result[0].JobQueueUri | Should -Match 'queue.core.windows.net'
        $Result[0].EncryptionKey | Should -Be 'abc123base64='
        ($Result[0] | Get-Member -Name SourceListItemUniqueIds -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }
}
