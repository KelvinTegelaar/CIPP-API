# New-GraphBulkRequest follows @odata.nextLink for every $batch item by re-batching the
# continuation pages. A continuation page that fails used to vanish without a trace: the parent
# item kept status 200 and only its first page, so a caller that treats "status < 400" as "the
# collection is complete" (the drift engine's stale-row prune does) worked from a partial list.
# On tenants with more than one page of settings-catalog policies a throttled page 2 therefore
# looked like "those policies are gone", their accepted drift rows were pruned, and they came
# back as New on the next run. These tests pin the retry and the incomplete marker.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-AuthorisedRequest { param($Uri, $TenantID) }
    function Get-GraphToken { param($tenantid, $scope, $AsApp) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter, $TableName) }
    function Update-AzDataTableEntity { param($Entity, [switch]$Force, $TableName) }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Headers, $ContentType, $Body) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-GraphBulkRequest.ps1')

    function New-BatchReply {
        param($Responses)
        [pscustomobject]@{ responses = @($Responses) }
    }
    function New-PageItem {
        param($Id, $Status = 200, $Values = @(), $NextLink, $Headers = $null, $Error = $null)
        $Body = [pscustomobject]@{ value = @($Values) }
        if ($NextLink) { $Body | Add-Member -NotePropertyName '@odata.nextLink' -NotePropertyValue $NextLink }
        if ($Error) { $Body | Add-Member -NotePropertyName 'error' -NotePropertyValue ([pscustomobject]@{ message = $Error }) }
        [pscustomobject]@{ id = $Id; status = $Status; headers = $Headers; body = $Body }
    }
}

Describe 'New-GraphBulkRequest continuation paging' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:Replies = [System.Collections.Generic.Queue[object]]::new()
        Mock Get-AuthorisedRequest { $true }
        Mock Get-GraphToken { @{} }
        Mock Get-CippTable { @{} }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Update-AzDataTableEntity {}
        Mock Start-Sleep {}
        Mock Invoke-CIPPRestMethod {
            $script:Calls.Add($Body)
            $script:Replies.Dequeue()
        }
        $script:Requests = @(@{ id = 'cp'; url = 'deviceManagement/configurationPolicies?$top=999'; method = 'GET' })
        $script:Next = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?$top=999&$skiptoken=page2'
    }

    It 'merges every continuation page into the parent item' {
        $script:Replies.Enqueue((New-BatchReply (New-PageItem -Id 'cp' -Values @(@{ id = 'p1' }, @{ id = 'p2' }) -NextLink $script:Next)))
        $script:Replies.Enqueue((New-BatchReply (New-PageItem -Id 'cp' -Values @(@{ id = 'p3' }))))

        $Result = @(New-GraphBulkRequest -Requests $script:Requests -tenantid 'contoso.onmicrosoft.com' -asapp $true)

        $Result.Count | Should -Be 1
        @($Result[0].body.value).id | Should -Be @('p1', 'p2', 'p3')
        $Result[0].PSObject.Properties['PagingIncomplete'] | Should -BeNullOrEmpty
        $script:Calls.Count | Should -Be 2
    }

    It 'retries a throttled continuation page once, honouring Retry-After' {
        $script:Replies.Enqueue((New-BatchReply (New-PageItem -Id 'cp' -Values @(@{ id = 'p1' }) -NextLink $script:Next)))
        $script:Replies.Enqueue((New-BatchReply (New-PageItem -Id 'cp' -Status 429 -Headers ([pscustomobject]@{ 'Retry-After' = '3' }) -Error 'throttled')))
        $script:Replies.Enqueue((New-BatchReply (New-PageItem -Id 'cp' -Values @(@{ id = 'p2' }))))

        $Result = @(New-GraphBulkRequest -Requests $script:Requests -tenantid 'contoso.onmicrosoft.com' -asapp $true -WarningAction SilentlyContinue)

        @($Result[0].body.value).id | Should -Be @('p1', 'p2')
        $Result[0].PSObject.Properties['PagingIncomplete'] | Should -BeNullOrEmpty
        $script:Calls.Count | Should -Be 3
        $script:Calls[2] | Should -Match 'skiptoken=page2'
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 3 }
    }

    It 'marks the parent incomplete when the continuation page keeps failing' {
        $script:Replies.Enqueue((New-BatchReply (New-PageItem -Id 'cp' -Values @(@{ id = 'p1' }) -NextLink $script:Next)))
        $script:Replies.Enqueue((New-BatchReply (New-PageItem -Id 'cp' -Status 429 -Error 'throttled')))
        $script:Replies.Enqueue((New-BatchReply (New-PageItem -Id 'cp' -Status 503 -Error 'busy')))

        $Result = @(New-GraphBulkRequest -Requests $script:Requests -tenantid 'contoso.onmicrosoft.com' -asapp $true -WarningVariable Warnings -WarningAction SilentlyContinue)

        @($Result[0].body.value).id | Should -Be @('p1')
        $Result[0].status | Should -Be 200
        $Result[0].PagingIncomplete | Should -BeTrue
        $Result[0].PagingError | Should -Match '503'
        $Result[0].PagingError | Should -Match 'busy'
        @($Warnings) | Where-Object { $_ -match 'incomplete' } | Should -Not -BeNullOrEmpty
        $script:Calls.Count | Should -Be 3
    }

    It 'marks the parent incomplete when the batch reply omits the continuation page' {
        $script:Replies.Enqueue((New-BatchReply (New-PageItem -Id 'cp' -Values @(@{ id = 'p1' }) -NextLink $script:Next)))
        $script:Replies.Enqueue((New-BatchReply @()))

        $Result = @(New-GraphBulkRequest -Requests $script:Requests -tenantid 'contoso.onmicrosoft.com' -asapp $true -WarningAction SilentlyContinue)

        @($Result[0].body.value).id | Should -Be @('p1')
        $Result[0].PagingIncomplete | Should -BeTrue
        $Result[0].PagingError | Should -Match 'missing'
    }

    It 'leaves items that never paged untouched' {
        $script:Replies.Enqueue((New-BatchReply @((New-PageItem -Id 'cp' -Values @(@{ id = 'p1' })), (New-PageItem -Id 'other' -Status 429 -Error 'throttled'))))

        $Result = @(New-GraphBulkRequest -Requests ($script:Requests + @(@{ id = 'other'; url = 'x'; method = 'GET' })) -tenantid 'contoso.onmicrosoft.com' -asapp $true)

        $Result.Count | Should -Be 2
        ($Result | Where-Object id -eq 'cp').PSObject.Properties['PagingIncomplete'] | Should -BeNullOrEmpty
        ($Result | Where-Object id -eq 'other').status | Should -Be 429
        $script:Calls.Count | Should -Be 1
    }
}
