# Pester tests for Resolve-CIPPSharePointLibraryCopyDestFolder.ps1

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Resolve-CIPPSharePointLibraryCopyDestFolder.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }

    function New-GraphGetRequest { param($uri, $tenantid, $asapp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Get-CippException {
        param($Exception)
        [PSCustomObject]@{
            NormalizedError = $Exception.Exception.Message ?? $Exception.Message
            RawError        = $Exception.Exception.Data['RawErrorBody'] ?? 'Not available'
        }
    }

    . $FunctionPath

    $Common = @{
        TenantFilter = 'contoso.com'
        SiteId       = 'site-b'
        ListId       = 'list-b'
        FolderName   = 'Archive - jane@contoso.com'
    }
    $script:FolderItem = [PSCustomObject]@{
        id     = 'item-1'
        name   = 'Archive - jane@contoso.com'
        webUrl = 'https://contoso.sharepoint.com/sites/b/Shared%20Documents/Archive%20-%20jane@contoso.com'
        folder = [PSCustomObject]@{ childCount = 0 }
    }
}

Describe 'Resolve-CIPPSharePointLibraryCopyDestFolder' {
    It 'looks the folder up by escaped path under the destination library drive root' {
        Mock New-GraphGetRequest { $script:FolderItem }

        $null = Resolve-CIPPSharePointLibraryCopyDestFolder @Common

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
            $uri -like 'https://graph.microsoft.com/v1.0/sites/site-b/lists/list-b/drive/root:/Archive%20-%20jane%40contoso.com?*'
        }
    }

    It 'reuses an existing folder and never POSTs' {
        Mock New-GraphGetRequest { $script:FolderItem }
        Mock New-GraphPOSTRequest { throw 'should not be called' }

        $Result = Resolve-CIPPSharePointLibraryCopyDestFolder @Common -Create

        $Result.ItemId | Should -Be 'item-1'
        $Result.WebUrl | Should -Be $script:FolderItem.webUrl
        $Result.Created | Should -Be $false
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'returns $null without -Create when the folder does not exist' {
        Mock New-GraphGetRequest { throw 'itemNotFound (404)' }
        Mock New-GraphPOSTRequest { throw 'should not be called' }

        Resolve-CIPPSharePointLibraryCopyDestFolder @Common | Should -BeNullOrEmpty
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'creates the folder with conflictBehavior fail when missing' {
        Mock New-GraphGetRequest { throw 'itemNotFound (404)' }
        Mock New-GraphPOSTRequest { $script:FolderItem }

        $Result = Resolve-CIPPSharePointLibraryCopyDestFolder @Common -Create

        $Result.Created | Should -Be $true
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Parsed = $body | ConvertFrom-Json
            $uri -eq 'https://graph.microsoft.com/v1.0/sites/site-b/lists/list-b/drive/root/children' -and
            $Parsed.name -eq 'Archive - jane@contoso.com' -and
            $null -ne $Parsed.folder -and
            $Parsed.'@microsoft.graph.conflictBehavior' -eq 'fail'
        }
    }

    It 'reuses the folder when a concurrent create wins the race' {
        $script:GetCalls = 0
        Mock New-GraphGetRequest {
            $script:GetCalls++
            if ($script:GetCalls -eq 1) { throw 'itemNotFound (404)' }
            $script:FolderItem
        }
        Mock New-GraphPOSTRequest { throw 'nameAlreadyExists (409)' }

        $Result = Resolve-CIPPSharePointLibraryCopyDestFolder @Common -Create

        $Result.ItemId | Should -Be 'item-1'
        $Result.Created | Should -Be $false
    }

    It 'recognises the conflict the way New-GraphPOSTRequest really reports it' {
        # New-GraphPOSTRequest throws Graph's normalised error.message and keeps the raw body
        # (with code nameAlreadyExists) in Exception.Data['RawErrorBody'].
        $script:GetCalls = 0
        Mock New-GraphGetRequest {
            $script:GetCalls++
            if ($script:GetCalls -eq 1) { throw 'itemNotFound (404)' }
            $script:FolderItem
        }
        Mock New-GraphPOSTRequest {
            $GraphException = [System.Exception]::new('Name already exists')
            $GraphException.Data['RawErrorBody'] = '{"error":{"code":"nameAlreadyExists","message":"Name already exists"}}'
            throw $GraphException
        }

        $Result = Resolve-CIPPSharePointLibraryCopyDestFolder @Common -Create

        $Result.ItemId | Should -Be 'item-1'
        $Result.Created | Should -Be $false
    }

    It 'reports the create failure when the conflict re-read also fails' {
        Mock New-GraphGetRequest { throw 'itemNotFound (404)' }
        Mock New-GraphPOSTRequest { throw 'nameAlreadyExists (409)' }

        { Resolve-CIPPSharePointLibraryCopyDestFolder @Common -Create } | Should -Throw '*Failed to create destination folder*nameAlreadyExists*'
    }

    It 'throws when an item with that name exists but is a file' {
        Mock New-GraphGetRequest {
            [PSCustomObject]@{ id = 'file-1'; name = 'Archive - jane@contoso.com'; file = [PSCustomObject]@{} }
        }

        { Resolve-CIPPSharePointLibraryCopyDestFolder @Common -Create } | Should -Throw '*is not a folder*'
    }

    It 'surfaces non-conflict create failures' {
        Mock New-GraphGetRequest { throw 'itemNotFound (404)' }
        Mock New-GraphPOSTRequest { throw 'accessDenied (403)' }

        { Resolve-CIPPSharePointLibraryCopyDestFolder @Common -Create } | Should -Throw '*Failed to create destination folder*accessDenied*'
    }
}
