# Pester tests for Start-CIPPSharePointLibraryCopy (destination / DestFolderName handling)

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StartPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Start-CIPPSharePointLibraryCopy.ps1'
    $FolderNamePath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPSharePointLibraryCopyFolderName.ps1'
    foreach ($Path in @($StartPath, $FolderNamePath)) {
        if (-not (Test-Path $Path)) { throw "Could not locate $Path" }
    }

    function New-GraphGetRequest { param($uri, $tenantid, $asapp) }
    function Test-CIPPSharePointLibraryCopyEligible { param($Template, $Title, $Name) }
    function Get-CIPPSharePointLibraryRootChildUris { param($TenantFilter, $SiteId, $SiteUrl, $ListId) }
    function Resolve-CIPPSharePointLibraryRootUri { param($TenantFilter, $SiteUrl, $SiteId, $ListId) }
    function Resolve-CIPPSharePointLibraryCopyDestFolder { param($TenantFilter, $SiteId, $ListId, $FolderName, [switch]$Create) }
    function Invoke-CIPPSharePointCreateCopyJobs { param($TenantFilter, $SourceSiteUrl, $ExportObjectUris, $DestinationUri, $NameConflictBehavior, $SameWebCopyMoveOptimization) }
    function Set-CIPPSharePointLibraryCopyOperation { param([string]$TenantFilter, [string]$OperationId, [hashtable]$Entity) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev) }

    . $StartPath
    . $FolderNamePath

    $BaseParams = @{
        TenantFilter = 'contoso.com'
        SourceSiteId = 'site-a'
        SourceListId = 'list-a'
        DestSiteId   = 'site-b'
        DestListId   = 'list-b'
        StartedBy    = 'admin@contoso.com'
    }
}

Describe 'Start-CIPPSharePointLibraryCopy' {
    BeforeEach {
        Mock New-GraphGetRequest {
            if ($uri -match '/sites/(site-[ab])/lists/(list-[ab])') {
                return [PSCustomObject]@{ id = $Matches[2]; displayName = "Library $($Matches[2])"; name = $Matches[2]; list = [PSCustomObject]@{ template = 'documentLibrary' } }
            }
            if ($uri -match '/sites/(site-[ab])') {
                return [PSCustomObject]@{ id = $Matches[1]; webUrl = "https://contoso.sharepoint.com/sites/$($Matches[1])"; displayName = "Site $($Matches[1])" }
            }
        }
        Mock Test-CIPPSharePointLibraryCopyEligible { [PSCustomObject]@{ Eligible = $true; Reason = $null } }
        Mock Get-CIPPSharePointLibraryRootChildUris {
            [PSCustomObject]@{
                ChildUris         = @('https://contoso.sharepoint.com/sites/site-a/Documents/Folder1', 'https://contoso.sharepoint.com/sites/site-a/Documents/file.docx')
                EligibleRootCount = 2
            }
        }
        Mock Resolve-CIPPSharePointLibraryRootUri {
            [PSCustomObject]@{
                SiteUrl           = $SiteUrl
                LibraryRootUri    = "$SiteUrl/Shared Documents"
                ServerRelativeUrl = '/sites/x/Shared Documents'
            }
        }
        Mock Resolve-CIPPSharePointLibraryCopyDestFolder {
            [PSCustomObject]@{
                ItemId  = 'folder-1'
                Name    = $FolderName
                WebUrl  = 'https://contoso.sharepoint.com/sites/site-b/Shared%20Documents/Archive%20-%20jane@contoso.com'
                Created = $true
            }
        }
        Mock Invoke-CIPPSharePointCreateCopyJobs {
            @([PSCustomObject]@{ JobId = 'job-1'; JobQueueUri = 'https://queue'; EncryptionKey = 'key' })
        }
        Mock Set-CIPPSharePointLibraryCopyOperation {}
        Mock Write-LogMessage {}
    }

    Context 'without DestFolderName' {
        It 'copies into the destination library root and never touches folders' {
            $Result = Start-CIPPSharePointLibraryCopy -Mode StartLibraryCopy @BaseParams

            Should -Invoke Resolve-CIPPSharePointLibraryCopyDestFolder -Times 0 -Exactly
            Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 1 -Exactly -ParameterFilter {
                $DestinationUri -eq 'https://contoso.sharepoint.com/sites/site-b/Shared Documents'
            }
            Should -Invoke Set-CIPPSharePointLibraryCopyOperation -Times 1 -Exactly -ParameterFilter {
                -not $Entity.ContainsKey('DestFolderName')
            }
            $Result.PSObject.Properties.Name | Should -Not -Contain 'DestFolderName'
            $Result.OperationId | Should -Not -BeNullOrEmpty
        }

        It 'returns the preflight shape unchanged' {
            $Result = Start-CIPPSharePointLibraryCopy -Mode PreflightLibraryCopy @BaseParams

            ($Result.PSObject.Properties.Name -join ',') | Should -Be 'EligibleRootCount,WarnLevel,Message'
            Should -Invoke Resolve-CIPPSharePointLibraryCopyDestFolder -Times 0 -Exactly
        }
    }

    Context 'with DestFolderName' {
        It 'creates or reuses the folder and targets it for every copy job' {
            $Result = Start-CIPPSharePointLibraryCopy -Mode StartLibraryCopy @BaseParams -DestFolderName ' Archive - jane@contoso.com '

            Should -Invoke Resolve-CIPPSharePointLibraryCopyDestFolder -Times 1 -Exactly -ParameterFilter {
                $Create -and $SiteId -eq 'site-b' -and $ListId -eq 'list-b' -and $FolderName -eq 'Archive - jane@contoso.com'
            }
            Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 1 -Exactly -ParameterFilter {
                $DestinationUri -eq 'https://contoso.sharepoint.com/sites/site-b/Shared%20Documents/Archive%20-%20jane@contoso.com'
            }
            $Result.DestFolderName | Should -Be 'Archive - jane@contoso.com'
            $Result.DestFolderCreated | Should -Be $true
        }

        It 'persists DestFolderName on the operation record' {
            $null = Start-CIPPSharePointLibraryCopy -Mode StartLibraryCopy @BaseParams -DestFolderName 'Archive - jane@contoso.com'

            Should -Invoke Set-CIPPSharePointLibraryCopyOperation -Times 1 -Exactly -ParameterFilter {
                $Entity.DestFolderName -eq 'Archive - jane@contoso.com' -and $Entity.ContainsKey('CopyJobInfos')
            }
        }

        It 'falls back to the library root URI plus folder name when Graph returns no webUrl' {
            Mock Resolve-CIPPSharePointLibraryCopyDestFolder {
                [PSCustomObject]@{ ItemId = 'folder-1'; Name = $FolderName; WebUrl = $null; Created = $false }
            }

            $Result = Start-CIPPSharePointLibraryCopy -Mode StartLibraryCopy @BaseParams -DestFolderName 'Archive'

            Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 1 -Exactly -ParameterFilter {
                $DestinationUri -eq 'https://contoso.sharepoint.com/sites/site-b/Shared Documents/Archive'
            }
            $Result.DestFolderCreated | Should -Be $false
        }

        It 'does not create the folder during preflight' {
            Mock Resolve-CIPPSharePointLibraryCopyDestFolder { $null }

            $Result = Start-CIPPSharePointLibraryCopy -Mode PreflightLibraryCopy @BaseParams -DestFolderName 'Archive'

            Should -Invoke Resolve-CIPPSharePointLibraryCopyDestFolder -Times 1 -Exactly -ParameterFilter { -not $Create }
            Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 0 -Exactly
            $Result.DestFolderName | Should -Be 'Archive'
            $Result.DestFolderExists | Should -Be $false
        }

        It 'rejects an invalid folder name before any SharePoint call' {
            { Start-CIPPSharePointLibraryCopy -Mode StartLibraryCopy @BaseParams -DestFolderName 'a/b' } | Should -Throw '*DestFolderName*'

            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 0 -Exactly
        }
    }
}
