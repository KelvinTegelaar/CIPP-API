# Pester tests for Start-CIPPOneDriveCopyToUser: preflight refusals, folder handling and job submission

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Start-CIPPOneDriveCopyToUser.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }

    function Get-CIPPOneDriveCopyUser { param($TenantFilter, $UserId, $Kind) }
    function New-GraphGetRequest { param($uri, $tenantid, $asapp, $noPagination, [switch]$SkipValueExtraction) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Invoke-CIPPSharePointCreateCopyJobs { param($TenantFilter, $SourceSiteUrl, $ExportObjectUris, $DestinationUri, $NameConflictBehavior, $SameWebCopyMoveOptimization, $IgnoreVersionHistory) }
    function Set-CIPPSharePointLibraryCopyOperation { param($TenantFilter, $OperationId, $Entity, $TableName) }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force, $TableName) }
    function Get-CIPPAzDataTableEntity { param($Filter, $TableName) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }

    . $FunctionPath
    # Partition keys: the real helper over a Get-Tenants that knows no tenant, so rows are keyed by the
    # lower-cased tenantFilter unless a test says otherwise.
    function Get-Tenants { param($TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPOneDriveCopyTenantKey.ps1')

    function New-TestUser([string]$Name, [int64]$Remaining = 10GB, [string]$DriveHost = 'contoso-my.sharepoint.com', $AccountEnabled = $true) {
        $Personal = "$($Name)_contoso_com"
        [pscustomobject]@{
            UserId            = "id-$Name"
            UserPrincipalName = "$Name@contoso.com"
            DriveId           = "drive-$Name"
            DriveWebUrl       = "https://$DriveHost/personal/$Personal/Documents"
            DriveHost         = $DriveHost
            SiteUrl           = "https://$DriveHost/personal/$Personal"
            QuotaRemaining    = $Remaining
            AccountEnabled    = $AccountEnabled
            UserType          = 'Member'
        }
    }
    # Splits delta items into pages linked by @odata.nextLink; the last page carries a deltaLink.
    function New-DeltaPages([object[]]$Items, [int]$PageSize = 1000) {
        $Pages = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt [Math]::Max(1, $Items.Count); $i += $PageSize) {
            $Pages.Add([pscustomobject]@{ value = @($Items | Select-Object -Skip $i -First $PageSize) })
        }
        for ($p = 0; $p -lt $Pages.Count; $p++) {
            if ($p -lt $Pages.Count - 1) {
                $Pages[$p] | Add-Member -NotePropertyName '@odata.nextLink' -NotePropertyValue "https://graph.microsoft.com/v1.0/drives/drive-jane/root/delta?token=p$($p + 1)"
            } else {
                $Pages[$p] | Add-Member -NotePropertyName '@odata.deltaLink' -NotePropertyValue 'https://graph.microsoft.com/v1.0/drives/drive-jane/root/delta?token=done'
            }
        }
        @($Pages)
    }
    function New-DeltaFile([string]$Name, [int64]$Size) { [pscustomobject]@{ id = "f-$Name"; name = $Name; size = $Size; file = @{ mimeType = 'text/plain' } } }
    function New-DeltaFolder([string]$Name) { [pscustomobject]@{ id = "d-$Name"; name = $Name; size = 0; folder = @{ childCount = 0 } } }
    $script:DeltaRoot = [pscustomobject]@{ id = 'root'; name = 'root'; size = 1510; folder = @{ childCount = 4 }; root = @{} }
    $script:Params = @{ TenantFilter = 'contoso.com'; Leaver = 'jane@contoso.com'; Recipients = @('bob@contoso.com'); StartedBy = 'admin@partner.com' }
}

Describe 'Start-CIPPOneDriveCopyToUser' {
    BeforeEach {
        $script:Users = @{
            'jane@contoso.com'  = New-TestUser 'jane' -AccountEnabled $false
            'bob@contoso.com'   = New-TestUser 'bob'
            'carol@contoso.com' = New-TestUser 'carol'
        }
        Mock Get-CIPPOneDriveCopyUser {
            $Found = $script:Users[$UserId]
            if (-not $Found) { throw [System.ArgumentException]::new("Recipient '$UserId' was not found in tenant contoso.com.") }
            $Found.PSObject.Copy()
        }
        $script:Children = @(
            [pscustomobject]@{ id = 'i1'; name = 'Projects'; size = 1000; folder = @{ childCount = 3 } }
            [pscustomobject]@{ id = 'i2'; name = 'Budget #1.xlsx'; size = 500; file = @{} }
            [pscustomobject]@{ id = 'i3'; name = 'Notebook'; size = 10; package = @{ type = 'oneNote' } }
            [pscustomobject]@{ id = 'i4'; name = 'odd'; size = 1 }
        )
        Mock New-GraphGetRequest { $script:Children } -ParameterFilter { $uri -like '*/root/children*' }
        # The whole OneDrive: 5 files (1,510 bytes) under the root items above, plus folders, the root
        # and a deleted item, none of which count.
        $script:DeltaPages = New-DeltaPages @(
            $script:DeltaRoot
            New-DeltaFolder 'Projects'
            New-DeltaFile 'a.txt' 400
            New-DeltaFile 'b.txt' 300
            New-DeltaFile 'c.txt' 300
            New-DeltaFile 'Budget #1.xlsx' 500
            [pscustomobject]@{ id = 'n'; name = 'Notebook'; size = 10; folder = @{}; package = @{ type = 'oneNote' } }
            New-DeltaFile 'Section.one' 10
            [pscustomobject]@{ id = 'gone'; name = 'old.txt'; size = 9999; file = @{}; deleted = @{ state = 'deleted' } }
        )
        Mock New-GraphGetRequest {
            $Page = if ($uri -match 'token=p(\d+)') { [int]$Matches[1] } else { 0 }
            $script:DeltaPages[$Page]
        } -ParameterFilter { $uri -like '*/root/delta*' }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'existing'; name = 'jane@contoso.com'; folder = @{ childCount = 1 } } } -ParameterFilter { $uri -like '*/root:/*' }
        Mock New-GraphPOSTRequest { [pscustomobject]@{ id = 'new-folder'; name = 'jane@contoso.com'; folder = @{} } }
        Mock Invoke-CIPPSharePointCreateCopyJobs {
            @($ExportObjectUris | ForEach-Object { [pscustomobject]@{ JobId = (New-Guid).Guid; JobQueueUri = 'https://q.queue.core.windows.net/x'; EncryptionKey = 'k' } })
        }
        Mock Set-CIPPSharePointLibraryCopyOperation {}
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-CIPPAzDataTableEntity {}
        Mock Write-LogMessage {}
        Mock Start-Sleep {}
    }

    Context 'operation id chosen by the offboarding job' {
        It 'stores the copy under the given id' {
            $Id = '11111111-2222-3333-4444-555555555555'
            (Start-CIPPOneDriveCopyToUser @script:Params -OperationId $Id).OperationId | Should -Be $Id
            Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -eq "PartitionKey eq 'contoso.com' and RowKey eq '$Id'" }
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq $Id -and $Entity.Kind -eq 'Operation' }
            Should -Invoke Set-CIPPSharePointLibraryCopyOperation -ParameterFilter { $OperationId -eq "$Id-r0" }
        }

        It 'refuses an id that is already in use, without writing anything' {
            Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = '11111111-2222-3333-4444-555555555555'; Kind = 'Operation' } }
            { Start-CIPPOneDriveCopyToUser @script:Params -OperationId '11111111-2222-3333-4444-555555555555' } | Should -Throw '*already exists*'
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'refuses an id that is not a GUID' {
            { Start-CIPPOneDriveCopyToUser @script:Params -OperationId "x' or RowKey ne '" } | Should -Throw '*not a valid operation id*'
            Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    Context 'partition key' {
        BeforeEach {
            $script:CustomerId = 'c0ffee00-1111-2222-3333-444444444444'
            Mock Get-Tenants { [pscustomobject]@{ customerId = $script:CustomerId } }
        }

        It 'stores the copy under the customerId, and still calls Graph with the tenantFilter given' {
            $Params = $script:Params.Clone()
            $Params.TenantFilter = 'Contoso.com'
            $null = Start-CIPPOneDriveCopyToUser @Params
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.Kind -eq 'Operation' -and $Entity.PartitionKey -ceq $script:CustomerId }
            Should -Invoke Set-CIPPSharePointLibraryCopyOperation -Times 1 -Exactly -ParameterFilter { $TenantFilter -ceq $script:CustomerId }
            Should -Invoke Get-CIPPOneDriveCopyUser -ParameterFilter { $TenantFilter -ceq 'Contoso.com' }
            Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -ParameterFilter { $TenantFilter -ceq 'Contoso.com' }
        }

        It 'refuses an id already used under the old raw-tenantFilter key' {
            $Id = '11111111-2222-3333-4444-555555555555'
            Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = $Id; Kind = 'Operation' } } -ParameterFilter { $Filter -ceq "PartitionKey eq 'Contoso.com' and RowKey eq '$Id'" }
            $Params = $script:Params.Clone()
            $Params.TenantFilter = 'Contoso.com'
            { Start-CIPPOneDriveCopyToUser @Params -OperationId $Id } | Should -Throw '*already exists*'
            Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -ceq "PartitionKey eq '$($script:CustomerId)' and RowKey eq '$Id'" }
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    It 'creates the UPN folder and submits KeepBoth copy jobs for every root item into it' {
        $Result = Start-CIPPOneDriveCopyToUser @script:Params

        $Result.OperationId | Should -Match '^[0-9a-f-]{36}$'
        $Result.FolderName | Should -Be 'jane@contoso.com'
        $Result.RootItemCount | Should -Be 3
        $Result.SourceFileCount | Should -Be 5
        $Result.SourceBytes | Should -Be 1510
        $Result.ExpectedBytes | Should -Be 1510
        $Result.Recipients[0].State | Should -Be 'Queued'
        $Result.Recipients[0].FolderCreated | Should -BeTrue
        $Result.Recipients[0].JobCount | Should -Be 3

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Body = $body | ConvertFrom-Json
            $uri -eq 'https://graph.microsoft.com/v1.0/drives/drive-bob/root/children' -and $Body.name -eq 'jane@contoso.com' -and $Body.'@microsoft.graph.conflictBehavior' -eq 'fail'
        }
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 1 -Exactly -ParameterFilter {
            $SourceSiteUrl -eq 'https://contoso-my.sharepoint.com/personal/jane_contoso_com' -and
            $DestinationUri -eq 'https://contoso-my.sharepoint.com/personal/bob_contoso_com/Documents/jane%40contoso.com' -and
            $NameConflictBehavior -eq 2 -and $IgnoreVersionHistory -eq $true -and
            @($ExportObjectUris).Count -eq 3 -and
            $ExportObjectUris[1] -eq 'https://contoso-my.sharepoint.com/personal/jane_contoso_com/Documents/Budget%20%231.xlsx'
        }
        Should -Invoke Set-CIPPSharePointLibraryCopyOperation -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'OneDriveCopyToUser' -and $OperationId -like '*-r0' -and $Entity.JobHandleCount -eq 3 -and $Entity.StartedBy -eq 'admin@partner.com'
        }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.Kind -eq 'Operation' -and $Entity.PartitionKey -eq 'contoso.com' -and $Entity.LeaverUPN -eq 'jane@contoso.com' -and $Entity.StartedBy -eq 'admin@partner.com' -and
            $Entity.SourceFileCount -eq 5 -and $Entity.SourceBytes -eq 1510 -and $Entity.RootItemCount -eq 3 -and -not $Entity.ContainsKey('RootItemEmpty')
        }
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
            $uri -like 'https://graph.microsoft.com/v1.0/drives/drive-jane/root/delta?*' -and $asapp -eq $true -and $noPagination -eq $true -and $SkipValueExtraction
        }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $message -like '*started by admin@partner.com*' -and $tenant -eq 'contoso.com' }
    }

    It 'reuses an existing UPN folder' {
        Mock New-GraphPOSTRequest { throw 'nameAlreadyExists: Name already exists' }
        $Result = Start-CIPPOneDriveCopyToUser @script:Params
        $Result.Recipients[0].FolderCreated | Should -BeFalse
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 1 -Exactly
    }

    It 'copies version history only when asked' {
        Start-CIPPOneDriveCopyToUser @script:Params -IncludeVersionHistory $true | Out-Null
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -ParameterFilter { $IgnoreVersionHistory -eq $false }
    }

    It 'submits jobs in batches of 100 root items' {
        $script:Children = @(1..250 | ForEach-Object { [pscustomobject]@{ id = "i$_"; name = "f$_.txt"; size = 1; file = @{} } })
        $Result = Start-CIPPOneDriveCopyToUser @script:Params
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 3 -Exactly
        $Result.Recipients[0].JobCount | Should -Be 250
    }

    Context 'SharePoint bundles root items into fewer jobs' {
        BeforeEach {
            # As seen live: items are bundled in submission order, two per job.
            Mock Invoke-CIPPSharePointCreateCopyJobs {
                for ($i = 0; $i -lt @($ExportObjectUris).Count; $i += 2) { [pscustomobject]@{ JobId = (New-Guid).Guid; JobQueueUri = 'https://q.queue.core.windows.net/x'; EncryptionKey = 'k' } }
            }
        }

        It 'starts a 7-item copy that SharePoint runs as 4 jobs (live fixture)' {
            $script:Children = @(1..7 | ForEach-Object { [pscustomobject]@{ id = "i$_"; name = "f$_.txt"; size = 0; file = @{} } })
            $Result = Start-CIPPOneDriveCopyToUser @script:Params
            $Result.Recipients[0].State | Should -Be 'Queued'
            $Result.Recipients[0].JobCount | Should -Be 4
            Should -Invoke Set-CIPPSharePointLibraryCopyOperation -Times 1 -Exactly -ParameterFilter { $Entity.JobHandleCount -eq 4 -and @($Entity.CopyJobInfos).Count -eq 4 }
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Error' }
        }

        It 'accepts bundled jobs across batches of 100' {
            $script:Children = @(1..250 | ForEach-Object { [pscustomobject]@{ id = "i$_"; name = "f$_.txt"; size = 1; file = @{} } })
            $Result = Start-CIPPOneDriveCopyToUser @script:Params
            Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 3 -Exactly
            $Result.Recipients[0].State | Should -Be 'Queued'
            $Result.Recipients[0].JobCount | Should -Be 125
        }
    }

    It 'marks a recipient Failed when SharePoint returns <Case>, and keeps the others' -ForEach @(
        @{ Case = 'no jobs'; Jobs = 0; Expected = '*returned 0 copy job(s) for 3 root item(s)*' }
        @{ Case = 'more jobs than root items'; Jobs = 4; Expected = '*returned 4 copy job(s) for 3 root item(s)*' }
    ) {
        $Params = $script:Params.Clone()
        $Params.Recipients = @('bob@contoso.com', 'carol@contoso.com')
        $script:JobsToReturn = $Jobs
        Mock Invoke-CIPPSharePointCreateCopyJobs {
            @(1..$script:JobsToReturn | Where-Object { $script:JobsToReturn -gt 0 } | ForEach-Object { [pscustomobject]@{ JobId = "j$_"; JobQueueUri = 'https://q.queue.core.windows.net/x'; EncryptionKey = 'k' } })
        } -ParameterFilter { $DestinationUri -like '*bob_contoso_com*' }
        $Result = Start-CIPPOneDriveCopyToUser @Params
        $Bob = $Result.Recipients | Where-Object UserPrincipalName -EQ 'bob@contoso.com'
        $Bob.State | Should -Be 'Failed'
        $Bob.Message | Should -BeLike $Expected
        ($Result.Recipients | Where-Object UserPrincipalName -EQ 'carol@contoso.com').State | Should -Be 'Queued'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            ($Entity.Recipients | ConvertFrom-Json | Where-Object UserPrincipalName -EQ 'bob@contoso.com').StartError -like '*copy job(s) for 3*'
        }
    }

    It 'fails a recipient when one batch of 100 gets no jobs, even if the total is in range' {
        $script:Children = @(1..150 | ForEach-Object { [pscustomobject]@{ id = "i$_"; name = "f$_.txt"; size = 1; file = @{} } })
        Mock Invoke-CIPPSharePointCreateCopyJobs {
            if (@($ExportObjectUris).Count -eq 100) { 1..60 | ForEach-Object { [pscustomobject]@{ JobId = "j$_"; JobQueueUri = 'https://q.queue.core.windows.net/x'; EncryptionKey = 'k' } } }
        }
        { Start-CIPPOneDriveCopyToUser @script:Params } | Should -Throw '*returned 0 copy job(s) for 50 root item(s)*'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'starts one copy per recipient and de-duplicates recipients' {
        $Params = $script:Params.Clone()
        $Params.Recipients = @('bob@contoso.com', 'carol@contoso.com', 'BOB@contoso.com ')
        $script:Users['BOB@contoso.com'] = $script:Users['bob@contoso.com']
        $Result = Start-CIPPOneDriveCopyToUser @Params
        @($Result.Recipients).Count | Should -Be 2
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 2 -Exactly
    }

    It 'refuses <Case> before writing anything' -ForEach @(
        @{ Case = 'a recipient without enough space'; Setup = { $script:Users['bob@contoso.com'] = New-TestUser 'bob' -Remaining 100 }; Recipients = @('bob@contoso.com'); Message = '*bob@contoso.com does not have enough space*' }
        @{ Case = 'a recipient in another tenant'; Setup = { $script:Users['bob@contoso.com'] = New-TestUser 'bob' -DriveHost 'fabrikam-my.sharepoint.com' }; Recipients = @('bob@contoso.com'); Message = '*not in the same tenant*' }
        @{ Case = 'the leaver as recipient'; Setup = {}; Recipients = @('jane@contoso.com'); Message = '*is the leaver*' }
        @{ Case = 'an unknown recipient among good ones'; Setup = {}; Recipients = @('bob@contoso.com', 'ghost@contoso.com'); Message = "*'ghost@contoso.com' was not found*" }
        @{ Case = 'an empty leaver OneDrive'; Setup = { $script:Children = @() }; Recipients = @('bob@contoso.com'); Message = '*has nothing to copy*' }
        @{ Case = 'more than 1,000 root items'; Setup = { $script:Children = @(1..1001 | ForEach-Object { [pscustomobject]@{ name = "f$_"; size = 1; file = @{} } }) }; Recipients = @('bob@contoso.com'); Message = '*1001 items at its root*' }
        @{ Case = 'more than 100,000 files and folders in the OneDrive'; Setup = { $File = New-DeltaFile 'x.txt' 1; $script:DeltaPages = New-DeltaPages (@($File) * 100001) 1000 }; Recipients = @('bob@contoso.com'); Message = '*more than 100000 files and folders*' }
        @{ Case = 'no recipients'; Setup = {}; Recipients = @(' '); Message = 'At least one recipient is required.' }
        @{ Case = 'too many recipients'; Setup = {}; Recipients = @(1..11 | ForEach-Object { "u$_@contoso.com" }); Message = 'At most 10 recipients*' }
        @{ Case = 'a guest recipient among good ones'; Setup = { Mock Get-CIPPOneDriveCopyUser { throw [System.ArgumentException]::new('Recipient g_x.com#EXT#@contoso.com is a guest. Only members of the tenant can receive the copy.') } -ParameterFilter { $UserId -like 'g_*' } }; Recipients = @('bob@contoso.com', 'g_x.com#EXT#@contoso.com'); Message = '*is a guest*' }
    ) {
        . $Setup
        $Params = $script:Params.Clone()
        $Params.Recipients = $Recipients
        { Start-CIPPOneDriveCopyToUser @Params } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage $Message
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Set-CIPPSharePointLibraryCopyOperation -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Info' }
    }

    It 'names the folder exactly after a <Case> leaver UPN and escapes it in every URI' -ForEach @(
        @{ Case = 'guest'; Upn = 'jo_fabrikam.com#EXT#@contoso.onmicrosoft.com'; Escaped = 'jo_fabrikam.com%23EXT%23%40contoso.onmicrosoft.com' }
        @{ Case = 'apostrophe and plus'; Upn = "o'brien+it@contoso.com"; Escaped = 'o%27brien%2Bit%40contoso.com' }
        @{ Case = 'unicode'; Upn = 'zoë@contoso.com'; Escaped = 'zo%C3%AB%40contoso.com' }
    ) {
        $Leaver = New-TestUser 'jane' -AccountEnabled $false
        $Leaver.UserPrincipalName = $Upn
        $script:Users[$Upn] = $Leaver
        $Params = $script:Params.Clone()
        $Params.Leaver = $Upn
        $script:Upn = $Upn
        $script:Escaped = $Escaped
        Mock New-GraphPOSTRequest { throw 'nameAlreadyExists: Name already exists' }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'existing'; name = $script:Upn; folder = @{} } } -ParameterFilter { $uri -like '*/root:/*' }

        $Result = Start-CIPPOneDriveCopyToUser @Params

        $Result.FolderName | Should -BeExactly $Upn
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { ($body | ConvertFrom-Json).name -ceq $script:Upn }
        # Looked up twice: the preflight name check, and after the creation conflict.
        Should -Invoke New-GraphGetRequest -Times 2 -Exactly -ParameterFilter { $uri -like "https://graph.microsoft.com/v1.0/drives/drive-bob/root:/$($script:Escaped)?*" }
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 1 -Exactly -ParameterFilter {
            $DestinationUri -ceq "https://contoso-my.sharepoint.com/personal/bob_contoso_com/Documents/$($script:Escaped)"
        }
    }

    It 'escapes root item names in the source URIs' {
        $script:Children = @([pscustomobject]@{ id = 'i1'; name = "Q1 #2 50% o'clock+ü.docx"; size = 1; file = @{} })
        Start-CIPPOneDriveCopyToUser @script:Params | Out-Null
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -ParameterFilter {
            $ExportObjectUris[0] -ceq 'https://contoso-my.sharepoint.com/personal/jane_contoso_com/Documents/Q1%20%232%2050%25%20o%27clock%2B%C3%BC.docx'
        }
    }

    It 'refuses the leaver as a recipient when one is given by UPN and the other by object id' {
        $script:Users['id-jane'] = $script:Users['jane@contoso.com']
        $Params = $script:Params.Clone()
        $Params.Recipients = @('id-jane')
        { Start-CIPPOneDriveCopyToUser @Params } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*is the leaver*'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'copies once to a recipient given both by UPN and by object id' {
        $script:Users['id-bob'] = $script:Users['bob@contoso.com']
        $Params = $script:Params.Clone()
        $Params.Recipients = @('bob@contoso.com', 'id-bob')
        $Result = Start-CIPPOneDriveCopyToUser @Params
        @($Result.Recipients).Count | Should -Be 1
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
    }

    It 'does not treat a non-conflict folder creation error as an existing folder' {
        Mock New-GraphGetRequest { throw 'itemNotFound: The resource could not be found.' } -ParameterFilter { $uri -like '*/root:/*' }
        Mock New-GraphPOSTRequest { throw 'accessDenied: Access denied' }
        { Start-CIPPOneDriveCopyToUser @script:Params } | Should -Throw '*Access denied*'
        # Only the preflight looked the name up; the failed creation is not followed by a lookup.
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/root:/*' }
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 0 -Exactly
    }

    It 'checks free space against the leaver total for every recipient' {
        $Params = $script:Params.Clone()
        $Params.Recipients = @('bob@contoso.com', 'carol@contoso.com')
        $script:Users['carol@contoso.com'] = New-TestUser 'carol' -Remaining 1509
        { Start-CIPPOneDriveCopyToUser @Params } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*carol@contoso.com does not have enough space: the copy needs 1510 bytes and 1509 are free*'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'warns, but starts, when a recipient quota cannot be read' {
        $script:Users['bob@contoso.com'].QuotaRemaining = $null
        (Start-CIPPOneDriveCopyToUser @script:Params).Warnings | Should -BeLike '*could not be read*'
    }

    It 'refuses when the recipient has a file named like the folder' {
        Mock New-GraphPOSTRequest { throw 'nameAlreadyExists: Name already exists' }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'a-file'; name = 'jane@contoso.com'; file = @{} } } -ParameterFilter { $uri -like '*/root:/*' }
        { Start-CIPPOneDriveCopyToUser @script:Params } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*already has a file named jane@contoso.com*'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 0 -Exactly
    }

    Context 'destination name checked for every recipient before any folder is created' {
        BeforeEach {
            $script:Params2 = $script:Params.Clone()
            $script:Params2.Recipients = @('bob@contoso.com', 'carol@contoso.com', 'dave@contoso.com')
            $script:Users['dave@contoso.com'] = New-TestUser 'dave'
            # bob: name free; carol: a folder already there; dave: <DaveHas>
            Mock New-GraphGetRequest { throw 'itemNotFound: The resource could not be found.' } -ParameterFilter { $uri -like '*/drives/drive-bob/root:/*' }
            Mock New-GraphGetRequest { [pscustomobject]@{ id = 'f-carol'; name = 'jane@contoso.com'; folder = @{ childCount = 0 } } } -ParameterFilter { $uri -like '*/drives/drive-carol/root:/*' }
        }

        It 'refuses with 400 and creates nothing when a later recipient has a <Case> with that name' -ForEach @(
            @{ Case = 'file'; Item = [pscustomobject]@{ id = 'x'; name = 'jane@contoso.com'; file = @{} } }
            @{ Case = 'OneNote notebook'; Item = [pscustomobject]@{ id = 'x'; name = 'jane@contoso.com'; package = @{ type = 'oneNote' } } }
        ) {
            $script:DaveItem = $Item
            Mock New-GraphGetRequest { $script:DaveItem } -ParameterFilter { $uri -like '*/drives/drive-dave/root:/*' }
            { Start-CIPPOneDriveCopyToUser @script:Params2 } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*dave@contoso.com already has a file named jane@contoso.com*'
            Should -Invoke New-GraphGetRequest -Times 3 -Exactly -ParameterFilter { $uri -like '*/root:/jane%40contoso.com?*' -and $asapp -eq $true }
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 0 -Exactly
            Should -Invoke Set-CIPPSharePointLibraryCopyOperation -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'names every recipient with a clash, together with other refusals' {
            Mock New-GraphGetRequest { [pscustomobject]@{ id = 'x'; name = 'jane@contoso.com'; file = @{} } } -ParameterFilter { $uri -like '*/drives/drive-dave/root:/*' }
            Mock New-GraphGetRequest { [pscustomobject]@{ id = 'y'; name = 'jane@contoso.com'; file = @{} } } -ParameterFilter { $uri -like '*/drives/drive-bob/root:/*' }
            $script:Params2.Recipients += 'nobody@contoso.com'
            $Err = { Start-CIPPOneDriveCopyToUser @script:Params2 } | Should -Throw -ExceptionType ([System.ArgumentException]) -PassThru
            $Err.Exception.Message | Should -BeLike '*nobody@contoso.com*'
            $Err.Exception.Message | Should -BeLike '*bob@contoso.com already has a file*'
            $Err.Exception.Message | Should -BeLike '*dave@contoso.com already has a file*'
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'starts when the name is free or already a folder everywhere' {
            Mock New-GraphGetRequest { throw 'itemNotFound: The resource could not be found.' } -ParameterFilter { $uri -like '*/drives/drive-dave/root:/*' }
            $Result = Start-CIPPOneDriveCopyToUser @script:Params2
            @($Result.Recipients | Where-Object State -EQ 'Queued').Count | Should -Be 3
            Should -Invoke New-GraphPOSTRequest -Times 3 -Exactly
        }

        It 'creates nothing when the check itself fails (not a not-found)' {
            Mock New-GraphGetRequest { throw 'serviceNotAvailable: 503' } -ParameterFilter { $uri -like '*/drives/drive-dave/root:/*' }
            { Start-CIPPOneDriveCopyToUser @script:Params2 } | Should -Throw '*503*'
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    It 'warns about root items over the 100 GB per-job limit' {
        $script:Users['bob@contoso.com'] = New-TestUser 'bob' -Remaining 1TB
        $script:Children = @([pscustomobject]@{ name = 'Huge'; size = 101GB; folder = @{} })
        (Start-CIPPOneDriveCopyToUser @script:Params).Warnings | Should -BeLike '*larger than 100 GB*'
    }

    It 'reports a recipient whose jobs fail to start as Failed and keeps the others' {
        $Params = $script:Params.Clone()
        $Params.Recipients = @('bob@contoso.com', 'carol@contoso.com')
        Mock Invoke-CIPPSharePointCreateCopyJobs { throw 'Access denied https://contoso-my.sharepoint.com/personal/x' } -ParameterFilter { $DestinationUri -like '*bob_contoso_com*' }
        $Result = Start-CIPPOneDriveCopyToUser @Params
        ($Result.Recipients | Where-Object UserPrincipalName -EQ 'bob@contoso.com').State | Should -Be 'Failed'
        ($Result.Recipients | Where-Object UserPrincipalName -EQ 'bob@contoso.com').Message | Should -Not -BeLike '*https://*'
        ($Result.Recipients | Where-Object UserPrincipalName -EQ 'carol@contoso.com').State | Should -Be 'Queued'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'throws when no recipient could start' {
        Mock Invoke-CIPPSharePointCreateCopyJobs { throw 'SharePoint CreateCopyJobs returned no job handles.' }
        { Start-CIPPOneDriveCopyToUser @script:Params } | Should -Throw '*failed to start for every recipient*'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }
    It 'refuses a leaver who <Case> before writing anything' -ForEach @(
        @{ Case = 'can still sign in'; Enabled = $true }
        @{ Case = 'has no accountEnabled value'; Enabled = $null }
    ) {
        $script:Users['jane@contoso.com'] = New-TestUser 'jane' -AccountEnabled $Enabled
        { Start-CIPPOneDriveCopyToUser @script:Params } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*jane@contoso.com can still sign in*'
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*/root/children*' }
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        Should -Invoke Invoke-CIPPSharePointCreateCopyJobs -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }
    Context 'sign-in block read straight after Disable sign in (offboarding)' {
        BeforeEach {
            $script:Users['jane@contoso.com'] = New-TestUser 'jane' -AccountEnabled $true
            # Graph reads the account as enabled this many more times before it shows the block.
            $script:EnabledReads = 2
            Mock New-GraphGetRequest {
                $script:EnabledReads--
                [pscustomobject]@{ id = 'id-jane'; accountEnabled = ($script:EnabledReads -ge 0) }
            } -ParameterFilter { $uri -like '*/users/id-jane?*accountEnabled*' }
        }

        It 'reads the leaver again with a backoff and starts once the block shows' {
            $Result = Start-CIPPOneDriveCopyToUser @script:Params -WaitForSignInBlock
            $Result.Recipients[0].State | Should -Be 'Queued'
            Should -Invoke Start-Sleep -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 5 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 10 }
            Should -Invoke New-GraphGetRequest -Times 3 -Exactly -ParameterFilter { $uri -like '*/users/id-jane?*accountEnabled*' -and $asapp -eq $true }
        }

        It 'refuses, writing nothing, when the leaver still reads as enabled after about 45 s' {
            $script:EnabledReads = 100
            { Start-CIPPOneDriveCopyToUser @script:Params -WaitForSignInBlock } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*jane@contoso.com can still sign in*'
            Should -Invoke Start-Sleep -Times 4 -Exactly
            (5 + 10 + 15 + 15) | Should -BeLessOrEqual 60
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'does not wait when the leaver already reads as blocked' {
            $script:Users['jane@contoso.com'] = New-TestUser 'jane' -AccountEnabled $false
            $null = Start-CIPPOneDriveCopyToUser @script:Params -WaitForSignInBlock
            Should -Invoke Start-Sleep -Times 0 -Exactly
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*accountEnabled*' }
        }

        It 'refuses at once without the switch (the HTTP endpoint)' {
            { Start-CIPPOneDriveCopyToUser @script:Params } | Should -Throw -ExpectedMessage '*can still sign in*'
            Should -Invoke Start-Sleep -Times 0 -Exactly
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*accountEnabled*' }
        }
    }

    Context 'source totals from the whole OneDrive (delta)' {
        It 'follows @odata.nextLink across pages and counts only current files' {
            $Items = @($script:DeltaRoot) + @(1..2500 | ForEach-Object { if ($_ % 5 -eq 0) { New-DeltaFolder "d$_" } else { New-DeltaFile "f$_" 3 } }) +
                @([pscustomobject]@{ id = 'gone'; name = 'gone.txt'; size = 7; file = @{}; deleted = @{ state = 'deleted' } })
            $script:DeltaPages = New-DeltaPages $Items 999
            $Result = Start-CIPPOneDriveCopyToUser @script:Params
            Should -Invoke New-GraphGetRequest -Times 3 -Exactly -ParameterFilter { $uri -like '*/root/delta*' }
            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/root/delta?token=p2' }
            $Result.SourceFileCount | Should -Be 2000
            $Result.SourceBytes | Should -Be 6000
        }

        It 'stops enumerating as soon as the cap is passed, before writing anything' {
            $File = New-DeltaFile 'x.txt' 1
            $script:DeltaPages = New-DeltaPages (@($File) * 150000) 1000
            { Start-CIPPOneDriveCopyToUser @script:Params } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*more than 100000 files and folders*'
            Should -Invoke New-GraphGetRequest -Times 101 -Exactly -ParameterFilter { $uri -like '*/root/delta*' }
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'accepts exactly 100,000 files and folders' {
            $File = New-DeltaFile 'x.txt' 1
            $script:Users['bob@contoso.com'] = New-TestUser 'bob' -Remaining 1TB
            $script:DeltaPages = New-DeltaPages (@($File) * 100000) 1000
            (Start-CIPPOneDriveCopyToUser @script:Params).SourceFileCount | Should -Be 100000
        }

        It 'checks free space against the files counted by delta, not the lagging root-item sizes' {
            # Live: a folder holding files reported size 0 straight after upload.
            $script:Children = @(
                [pscustomobject]@{ id = 'i1'; name = 'Fresh'; size = 0; folder = @{ childCount = 2 } }
                [pscustomobject]@{ id = 'i2'; name = 'big.bin'; size = 2068334; file = @{} }
            )
            $script:DeltaPages = New-DeltaPages @($script:DeltaRoot, (New-DeltaFolder 'Fresh'), (New-DeltaFile 'a.txt' 29), (New-DeltaFile 'b.txt' 31), (New-DeltaFile 'big.bin' 2068334))
            $script:Users['bob@contoso.com'] = New-TestUser 'bob' -Remaining 2068393
            { Start-CIPPOneDriveCopyToUser @script:Params } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*needs 2068394 bytes and 2068393 are free*'
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly

            $script:Users['bob@contoso.com'] = New-TestUser 'bob' -Remaining 2068394
            $Result = Start-CIPPOneDriveCopyToUser @script:Params
            $Result.SourceBytes | Should -Be 2068394
            $Result.SourceFileCount | Should -Be 3
        }

        It 'starts a copy of a OneDrive holding only an empty folder, expecting no files' {
            $script:Children = @([pscustomobject]@{ id = 'i1'; name = 'Empty'; size = 0; folder = @{ childCount = 0 } })
            $script:DeltaPages = New-DeltaPages @($script:DeltaRoot, (New-DeltaFolder 'Empty'))
            $Result = Start-CIPPOneDriveCopyToUser @script:Params
            $Result.Recipients[0].State | Should -Be 'Queued'
            $Result.SourceFileCount | Should -Be 0
            $Result.SourceBytes | Should -Be 0
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.SourceFileCount -eq 0 -and $Entity.SourceBytes -eq 0 }
        }
    }
}
