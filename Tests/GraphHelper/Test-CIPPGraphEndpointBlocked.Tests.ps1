# Test-CIPPGraphEndpointBlocked — customer-content Graph path blocklist for arbitrary Graph proxies.
using namespace System.Net

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $env:CIPPRootPath = $RepoRoot
    $script:CippGraphEndpointBlocklist = $null

    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'public class HttpResponseContext { public object StatusCode; public object Body; public string ContentType; public object Headers; }'
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Test-CIPPGraphEndpointBlocked.ps1')
}

Describe 'Test-CIPPGraphEndpointBlocked' {
    BeforeEach {
        $script:CippGraphEndpointBlocklist = $null
    }

    Context 'blocked paths' {
        It 'blocks OneDrive drive item paths' {
            Test-CIPPGraphEndpointBlocked -Uri 'users/user@contoso.com/drive/items/ABC' | Should -BeTrue
        }

        It 'blocks full Graph drive URIs' {
            Test-CIPPGraphEndpointBlocked -Uri 'https://graph.microsoft.com/v1.0/users/x/drive/root/children' | Should -BeTrue
        }

        It 'blocks mailbox messages' {
            Test-CIPPGraphEndpointBlocked -Uri 'users/x/messages' | Should -BeTrue
        }

        It 'blocks mail MIME $value' {
            Test-CIPPGraphEndpointBlocked -Uri 'users/x/messages/y/$value' | Should -BeTrue
        }

        It 'blocks chats' {
            Test-CIPPGraphEndpointBlocked -Uri 'users/x/chats' | Should -BeTrue
        }

        It 'blocks calendar events' {
            Test-CIPPGraphEndpointBlocked -Uri 'users/x/events' | Should -BeTrue
        }

        It 'blocks group conversations' {
            Test-CIPPGraphEndpointBlocked -Uri 'groups/x/conversations' | Should -BeTrue
        }

        It 'blocks /content downloads' {
            Test-CIPPGraphEndpointBlocked -Uri 'drives/x/items/y/content' | Should -BeTrue
        }

        It 'blocks OData key syntax on <Uri>' -ForEach @(
            @{ Uri = "users/x/messages('m1')" }
            @{ Uri = "users/x/events('e1')" }
            @{ Uri = "users/x/contacts('c1')" }
            @{ Uri = "users/x/chats('c1')" }
            @{ Uri = "drives('b!abc')/root/children" }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeTrue
        }

        It 'blocks percent-encoded path <Uri>' -ForEach @(
            @{ Uri = 'users/x/%64rive/items/y' }
            @{ Uri = 'users/x/drive%2Fitems' }
            @{ Uri = 'users/x/%256Dessages' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeTrue
        }

        It 'blocks alternate driveItem route <Uri>' -ForEach @(
            @{ Uri = 'sites/s/lists/l/items/i/driveItem' }
            @{ Uri = 'sites/s/lists/l/items/i/driveItem/thumbnails' }
            @{ Uri = 'shares/u!abc/driveItem' }
            @{ Uri = 'shares/u!abc/root' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeTrue
        }

        It 'blocks $expand in the query string of <Uri>' -ForEach @(
            @{ Uri = 'sites/s/lists/l/items?$expand=driveItem' }
            @{ Uri = 'sites/s/lists/l/items?$expand=fields,driveItem($select=id)' }
            @{ Uri = 'users/x/mailFolders/inbox?$expand=messages' }
            @{ Uri = 'sites/s/lists/l/items?%24expand=driveItem' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeTrue
        }

        It 'blocks personal contacts <Uri>' -ForEach @(
            @{ Uri = 'users/x/contacts' }
            @{ Uri = 'me/contacts' }
            @{ Uri = 'users/x/contactFolders/f/contacts/c' }
            @{ Uri = 'users/x?$expand=contacts' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeTrue
        }

        It 'blocks user-content endpoint <Uri> (<Id>)' -ForEach @(
            @{ Uri = 'users/x/todo/lists/l/tasks'; Id = 'todo-tasks' }
            @{ Uri = "users/x/todo/lists('l')/tasks/t/checklistItems"; Id = 'todo-tasks' }
            @{ Uri = 'users/x/todo/lists?$expand=tasks'; Id = 'todo-tasks' }
            @{ Uri = 'users/x/planner/tasks'; Id = 'planner-tasks' }
            @{ Uri = 'planner/tasks/t/details'; Id = 'planner-tasks' }
            @{ Uri = 'planner/plans/p/buckets/b/tasks'; Id = 'planner-tasks' }
            @{ Uri = 'planner/plans/p?$expand=tasks'; Id = 'planner-tasks' }
            @{ Uri = 'sites/s/pages'; Id = 'site-pages' }
            @{ Uri = 'sites/s/pages/p/microsoft.graph.sitePage?$expand=canvasLayout'; Id = 'site-pages' }
            @{ Uri = 'sites/s/lists/l/items'; Id = 'list-items' }
            @{ Uri = "sites/s/lists('l')/items('1')/fields"; Id = 'list-items' }
            @{ Uri = 'sites/s/lists/l?$expand=items'; Id = 'list-items' }
            @{ Uri = 'copilot/users/u/interactionHistory/getAllEnterpriseInteractions'; Id = 'copilot-interactions' }
            @{ Uri = 'users/u/aiInteractionHistory/getAllEnterpriseInteractions'; Id = 'copilot-interactions' }
            @{ Uri = 'teams/t/channels/getAllMessages'; Id = 'mail-messages' }
            @{ Uri = 'users/u/chats/getAllRetainedMessages'; Id = 'mail-messages' }
            @{ Uri = 'teams/t/channels/getAllRetainedMessages'; Id = 'mail-messages' }
            @{ Uri = 'users/u/mailFolders/inbox/messages/m/attachments'; Id = 'mail-messages' }
            @{ Uri = 'groups/g/threads/t/posts/p/attachments'; Id = 'mail-attachments' }
            @{ Uri = "users/u/messages('m')/attachments('a')/content"; Id = 'file-content' }
            @{ Uri = 'users/u/events/e/attachments/a/content'; Id = 'file-content' }
            @{ Uri = 'users/u/adhocCalls/c/transcripts/t/metadataContent'; Id = 'adhoc-calls' }
            @{ Uri = 'users/u/adhocCalls/getAllTranscripts'; Id = 'adhoc-calls' }
            @{ Uri = 'users/u/adhocCalls/c/recordings'; Id = 'adhoc-calls' }
            @{ Uri = 'users/u/insights/used'; Id = 'document-insights' }
            @{ Uri = 'me/insights/trending/i/resource'; Id = 'document-insights' }
            @{ Uri = 'users/u?$expand=insights'; Id = 'document-insights' }
            @{ Uri = 'external/connections/contosohr/items/TSP228082938'; Id = 'external-items' }
            @{ Uri = 'external/connections/c?$expand=items'; Id = 'external-items' }
            @{ Uri = "external/connections('c')/items('i')"; Id = 'external-items' }
            @{ Uri = 'solutions/bookingBusinesses/b@contoso.com/customers'; Id = 'bookings-customers' }
            @{ Uri = "solutions/bookingBusinesses('b')/appointments/a"; Id = 'bookings-customers' }
            @{ Uri = 'solutions/virtualEvents/webinars/w/registrations'; Id = 'virtual-event-attendees' }
            @{ Uri = 'solutions/virtualEvents/townhalls/t/sessions/s/attendanceReports'; Id = 'virtual-event-attendees' }
            @{ Uri = "users/u/calendar/reminderView(startDateTime='2026-01-01',endDateTime='2026-02-01')"; Id = 'calendar-events' }
            @{ Uri = 'users/u/outlook/taskFolders/f/tasks'; Id = 'todo-tasks' }
            @{ Uri = 'users/u/planner/myDayTasks'; Id = 'planner-tasks' }
            @{ Uri = 'users/u/planner/all/delta'; Id = 'planner-tasks' }
            @{ Uri = 'sites/s/items/i'; Id = 'list-items' }
            @{ Uri = 'users/u/chats:'; Id = 'chats' }
            @{ Uri = 'users/u/people'; Id = 'people' }
            @{ Uri = 'security/cases/ediscoveryCases/c/operations/o'; Id = 'ediscovery' }
        ) {
            { Test-CIPPGraphEndpointBlocked -Uri $Uri -Throw } | Should -Throw -ExpectedMessage "*($Id)*"
        }

        It 'blocks URI normalisation trick <Uri>' -ForEach @(
            @{ Uri = 'users/x/messages#' }
            @{ Uri = 'users/x/drive#frag' }
            @{ Uri = 'https://graph.microsoft.com:443/beta/users/x/chats#' }
            @{ Uri = 'https://graph.microsoft.com/beta/users/x\drive\items\y' }
            @{ Uri = 'https://graph.microsoft.com/beta/x/../shares/u!abc/root' }
            @{ Uri = 'users/x\drive\items\y' }
            @{ Uri = 'x/../shares/u!abc/root' }
            @{ Uri = './shares/u!abc/root' }
            @{ Uri = 'users/x/messages.' }
            @{ Uri = 'users/x/messages%20' }
            @{ Uri = 'users/x/drive. /items' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeTrue
        }

        It 'blocks encoding trick <Uri>' -ForEach @(
            @{ Uri = 'sites/s/lists/l?$expand=fields, driveItem' }
            @{ Uri = 'sites/s/lists/l?$expand=fields,+driveItem' }
            @{ Uri = 'sites/s?$expand=%09driveItem' }
            @{ Uri = 'sites/s?$expand=driveItem%26x%3D1' }
            @{ Uri = 'users/x?%20$expand=messages' }
            @{ Uri = 'users/x??$expand=messages' }
            @{ Uri = 'users/x?%2524EXPAND=messages' }
            @{ Uri = 'users/x/%2525252525256Dessages' }
            @{ Uri = 'users/x/drive%3F' }
            @{ Uri = 'users/x/drive%23' }
            @{ Uri = 'users/x/%u006Dessages' }
            @{ Uri = 'users/x/messages%00' }
            @{ Uri = 'users/x/mess%E2%80%8Bages' }
            @{ Uri = "users/x/messages.('m')" }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeTrue
        }

        It 'only exempts allowed prefixes as whole segments <Uri>' -ForEach @(
            @{ Uri = 'users/u/mailFolders/xserviceAnnouncement/messages' }
            @{ Uri = 'users/u/serviceAnnouncement/messages' }
            @{ Uri = 'blueprint/shares/u!abc/root' }
            @{ Uri = 'sites/s/xphoto/$value' }
            @{ Uri = 'sites/s/x/48x48/$value' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeTrue
        }

        It 'fails closed on input that makes a pattern backtrack' {
            $Uri = 'sites/' + ('lists(a)/' * 20000) + 'x'
            { Test-CIPPGraphEndpointBlocked -Uri $Uri -Throw } | Should -Throw -ExpectedMessage '*could not be checked in time*'
        }

        It 'blocks $expand passed separately via -Expand' {
            Test-CIPPGraphEndpointBlocked -Uri 'sites/s' -Expand 'lists,driveItem' | Should -BeTrue
        }
    }

    Context 'allowed paths' {
        It 'allows directory users list' {
            Test-CIPPGraphEndpointBlocked -Uri 'users' | Should -BeFalse
        }

        It 'allows Message Center messages' {
            Test-CIPPGraphEndpointBlocked -Uri 'admin/serviceAnnouncement/messages' | Should -BeFalse
        }

        It 'allows user profile photo $value' {
            Test-CIPPGraphEndpointBlocked -Uri 'users/x/photo/$value' | Should -BeFalse
        }

        It 'allows sized profile photo $value' {
            Test-CIPPGraphEndpointBlocked -Uri 'users/x/photos/48x48/$value' | Should -BeFalse
        }

        It 'allows contentTypes (not /content)' {
            Test-CIPPGraphEndpointBlocked -Uri 'sites/x/contentTypes' | Should -BeFalse
        }

        It 'allows empty Uri' {
            Test-CIPPGraphEndpointBlocked -Uri '' | Should -BeFalse
        }

        It 'allows a harmless $expand' {
            Test-CIPPGraphEndpointBlocked -Uri 'groups?$expand=members($select=id)' -Expand 'owners' | Should -BeFalse
        }

        It 'allows ordinary queries with spaces and functions <Uri>' -ForEach @(
            @{ Uri = "users?`$filter=startswith(displayName,'drive')&`$select=id,displayName" }
            @{ Uri = 'groups?$expand=members($select=id, displayName)' }
            @{ Uri = 'users/x?$expand=manager($levels=max;$select=id)' }
            @{ Uri = "deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'" }
            @{ Uri = "reports/getOffice365ActiveUserDetail(period='D7')" }
            @{ Uri = 'users?$search="displayName:messages"' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeFalse
        }

        It 'allows admin and device-secret endpoints <Uri>' -ForEach @(
            @{ Uri = 'admin/people/pronouns' }
            @{ Uri = 'deviceManagement/autopilotEvents' }
            @{ Uri = 'deviceManagement/managedDevices/d/detectedApps' }
            @{ Uri = 'groups/g/transitiveMembers/microsoft.graph.group?$select=id,displayName' }
            @{ Uri = 'users/u/authentication/methods?$top=99' }
            @{ Uri = "reports/getMailboxUsageDetail(period='D7')" }
            @{ Uri = 'directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members' }
            @{ Uri = 'organization/o/branding' }
            @{ Uri = 'informationProtection/bitlocker/recoveryKeys/k?$select=key' }
            @{ Uri = 'directory/deviceLocalCredentials/d?$select=credentials' }
            @{ Uri = 'deviceManagement/managedDevices/d/getFileVaultKey' }
            @{ Uri = "deviceManagement/deviceConfigurations('c')/getOmaSettingPlainTextValue(secretReferenceValueId='s')" }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeFalse
        }

        It 'allows directory org contacts <Uri>' -ForEach @(
            @{ Uri = 'contacts' }
            @{ Uri = '/contacts' }
            @{ Uri = 'contacts/c1/memberOf' }
            @{ Uri = "contacts('c1')" }
            @{ Uri = 'https://graph.microsoft.com/beta/contacts?$select=id,displayName' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeFalse
        }

        It 'allows metadata-only endpoint <Uri>' -ForEach @(
            @{ Uri = 'users/x/todo/lists' }
            @{ Uri = 'groups/g/planner/plans' }
            @{ Uri = 'planner/plans/p/details' }
            @{ Uri = 'planner/plans/p/buckets' }
            @{ Uri = 'sites/s/lists' }
            @{ Uri = 'sites/s/lists/l/columns' }
            @{ Uri = 'sites/s/lists?$expand=columns' }
            @{ Uri = 'admin/serviceAnnouncement?$expand=messages' }
            @{ Uri = 'deviceManagement/notificationMessageTemplates/t/localizedNotificationMessages' }
            @{ Uri = 'admin/serviceAnnouncement/messages/m/attachments' }
            @{ Uri = "admin/serviceAnnouncement/messages('m')/attachments/a/content" }
            @{ Uri = 'admin/serviceAnnouncement/messages/m?$expand=attachments' }
            @{ Uri = 'external/connections' }
            @{ Uri = 'external/connections/c/schema' }
            @{ Uri = 'solutions/bookingBusinesses' }
            @{ Uri = 'solutions/bookingBusinesses/b/services' }
            @{ Uri = 'solutions/virtualEvents/webinars' }
            @{ Uri = 'solutions/virtualEvents/webinars/w/sessions' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeFalse
        }

        It 'allows print shares <Uri>' -ForEach @(
            @{ Uri = 'print/shares' }
            @{ Uri = 'print/shares/s1/allowedUsers' }
            @{ Uri = 'https://graph.microsoft.com/beta/print/shares?$top=5' }
        ) {
            Test-CIPPGraphEndpointBlocked -Uri $Uri | Should -BeFalse
        }
    }

    Context '-Throw' {
        It 'throws with id and reason for a blocked path' {
            { Test-CIPPGraphEndpointBlocked -Uri 'users/x/messages' -Throw } |
                Should -Throw -ExpectedMessage '*mail-messages*'
        }

        It 'throw message includes the reason text' {
            { Test-CIPPGraphEndpointBlocked -Uri 'users/x/drive/items/y' -Throw } |
                Should -Throw -ExpectedMessage '*downloadUrl*'
        }

        It 'does not throw for an allowed path' {
            { Test-CIPPGraphEndpointBlocked -Uri 'users' -Throw } | Should -Not -Throw
        }

        It 'emits nothing for an allowed path so bare guard calls do not leak into caller output' {
            @(Test-CIPPGraphEndpointBlocked -Uri 'users' -Throw).Count | Should -Be 0
            @(Test-CIPPGraphEndpointBlocked -Uri '' -Throw).Count | Should -Be 0
        }
    }
}

Describe 'Get-GraphRequestList blocklist gate' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
        $env:CIPPRootPath = $RepoRoot
        $script:CippGraphEndpointBlocklist = $null

        function New-GraphGetRequest { param([Parameter(ValueFromRemainingArguments)]$Rest) $script:GraphCalled = $true; [pscustomobject]@{ id = '1' } }
        function Get-StringHash { param($String) 'hash' }
        function Get-Tenants { param([switch]$IncludeErrors) @() }
        function Get-CIPPTextReplacement {
            param($TenantFilter, $Text)
            if ($Text -isnot [string]) { return $Text }
            $Text -replace '%d%', 'drive' -replace '%tenantid%', '00000000-0000-0000-0000-000000000001'
        }

        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphRequests/Get-GraphRequestList.ps1')
    }

    BeforeEach {
        $script:GraphCalled = $false
    }

    It 'throws with reason for a blocked Endpoint' {
        { Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'users/x/drive/items/y' -SkipCache } |
            Should -Throw -ExpectedMessage '*drive-trees*downloadUrl*'
        $script:GraphCalled | Should -BeFalse
    }

    It 'blocks a sensitive $expand parameter' {
        { Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'sites/s' -Parameters @{ '$expand' = 'driveItem' } -SkipCache } |
            Should -Throw -ExpectedMessage '*drive-item*'
        $script:GraphCalled | Should -BeFalse
    }

    It 'blocks a sensitive $expand when UseBatchExpand keeps it out of the query' {
        { Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'users' -Parameters @{ '$expand' = 'messages' } -UseBatchExpand -SkipCache } |
            Should -Throw -ExpectedMessage '*mail-messages*'
    }

    It 'blocks a forged nextLink' {
        { Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'users' -nextLink 'https://graph.microsoft.com/beta/users/x/drive/root/children' -ManualPagination -SkipCache } |
            Should -Throw -ExpectedMessage '*drive-trees*'
        $script:GraphCalled | Should -BeFalse
    }

    It 'blocks a fragment-truncated Endpoint' {
        { Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'users/x/messages#' -SkipCache } |
            Should -Throw -ExpectedMessage '*mail-messages*'
        $script:GraphCalled | Should -BeFalse
    }

    It 'blocks a nextLink that relies on backslash or dot-segment normalisation' {
        { Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'users' -nextLink 'https://graph.microsoft.com/beta/users/x\drive\items\y' -ManualPagination -SkipCache } |
            Should -Throw -ExpectedMessage '*drive-trees*'
        { Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'users' -nextLink 'https://graph.microsoft.com/beta/x/../shares/u!abc/root' -ManualPagination -SkipCache } |
            Should -Throw -ExpectedMessage '*shares*'
        $script:GraphCalled | Should -BeFalse
    }

    It 'blocks a custom variable that resolves to a blocked path' {
        { Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'users/x/%d%/items/y' -SkipCache } |
            Should -Throw -ExpectedMessage '*drive-trees*'
        $script:GraphCalled | Should -BeFalse
    }

    It 'allows a built-in variable that resolves to an allowed path' {
        Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'organization/%tenantid%/branding' -SkipCache | Out-Null
        $script:GraphCalled | Should -BeTrue
    }

    It 'allows a normal endpoint' {
        Get-GraphRequestList -TenantFilter 'contoso.onmicrosoft.com' -Endpoint 'users' -Parameters @{ '$select' = 'id' } -SkipCache | Out-Null
        $script:GraphCalled | Should -BeTrue
    }
}

Describe 'Invoke-ListGraphRequest blocklist gate' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
        $env:CIPPRootPath = $RepoRoot
        $script:CippGraphEndpointBlocklist = $null

        # Azure Functions resolves [HttpStatusCode]; accelerate it for local Pester.
        $Accelerators = [powershell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
        if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
            $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
        }

        function Write-LogMessage { param($headers, $API, $message, $Sev) }
        function New-GraphGetRequest { throw 'New-GraphGetRequest must not be called for blocked endpoints' }
        function Get-NormalizedError { param($Message) $Message }
        function Get-Tenants { @() }

        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphRequests/Get-GraphRequestList.ps1')
        . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ListGraphRequest.ps1')
    }

    It 'returns BadRequest with reason and does not call Graph for a blocked Endpoint' {
        $Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListGraphRequest' }
            Headers = @{}
            Query   = @{
                Endpoint     = 'users/x/drive/items/y'
                TenantFilter = 'contoso.onmicrosoft.com'
            }
        }
        $Result = Invoke-ListGraphRequest -Request $Request -TriggerMetadata @{ Headers = @{ Referer = 'https://example.com/' } }

        $Result.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Result.Body | Should -Match 'drive-trees'
        $Result.Body | Should -Match 'downloadUrl'
    }

    It 'blocks a sensitive $expand query parameter on an allowed Endpoint' {
        $Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListGraphRequest' }
            Headers = @{}
            Query   = @{
                Endpoint     = 'sites/s'
                '$expand'    = 'driveItem'
                TenantFilter = 'contoso.onmicrosoft.com'
            }
        }
        $Result = Invoke-ListGraphRequest -Request $Request -TriggerMetadata @{ Headers = @{ Referer = 'https://example.com/' } }

        $Result.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Result.Body | Should -Match 'drive-item'
    }
}

Describe 'Invoke-ListGraphBulkRequest blocklist gate' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
        $env:CIPPRootPath = $RepoRoot
        $script:CippGraphEndpointBlocklist = $null

        function New-GraphBulkRequest { throw 'New-GraphBulkRequest must not be called for blocked endpoints' }

        . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ListGraphBulkRequest.ps1')
    }

    It 'returns BadRequest with reason and does not call Graph for a blocked url' {
        $Request = [pscustomobject]@{
            Body = @{
                tenantFilter = 'contoso.onmicrosoft.com'
                requests     = @(
                    @{ id = '1'; method = 'GET'; url = 'users/x/messages' }
                )
            }
        }
        $Result = Invoke-ListGraphBulkRequest -Request $Request -TriggerMetadata @{}

        $Result.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Result.Body | Should -Match 'mail-messages'
    }
}
