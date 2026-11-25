BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-Tenants { [CmdletBinding()] param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPDefenderIndicator { param($TenantFilter, $PageSize) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type, $scope, $AsApp, $maxRetries) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    function New-CippQueueEntry { param($Name, $Link, $Reference, $TotalTasks) }
    function Start-CIPPOrchestrator { [CmdletBinding()] param($InputObject) }
    function Update-CippQueueEntry { param($RowKey, $Status) }
    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-CippApiClient { param($AppId) }
    foreach ($Helper in 'Get-CippErrorStatusCode.ps1', 'Get-CippBulkStatusCode.ps1', 'Get-CIPPTenantLookup.ps1', 'Add-CIPPDefenderIndicator.ps1', 'Push-ExecAddDefenderIndicator.ps1', 'Write-LogMessage.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Helper -File | Select-Object -First 1 -ExpandProperty FullName)
    }
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Defender/Invoke-AddDefenderIndicator.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:Sha256 = 'a3f5' * 16
    $script:TenantA = [pscustomobject]@{ customerId = '0b5ee4a1-0000-4000-8000-0000000000a1'; defaultDomainName = 'a.com'; initialDomainName = 'a.onmicrosoft.com' }

    function New-Principal ([string]$UserDetails) {
        [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((@{ userDetails = $UserDetails; userRoles = @('editor'); claims = @(@{ typ = 'name'; val = 'Tech' }) } | ConvertTo-Json -Compress -Depth 5)))
    }
    function New-Request ([hashtable]$Body, [hashtable]$Headers = @{ 'x-ms-client-principal' = (New-Principal 'tech@msp.example'); 'x-ms-client-principal-idp' = 'azureStaticWebApps'; 'x-forwarded-for' = '198.51.100.20:51234, 10.0.0.4' }) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'AddDefenderIndicator' }; Headers = $Headers; Body = [pscustomobject]$Body }
    }
    function ConvertTo-Canonical ($Value) {
        if ($Value -is [System.Collections.IDictionary]) {
            $Sorted = [ordered]@{}
            foreach ($Key in @($Value.Keys | Sort-Object)) { $Sorted[$Key] = ConvertTo-Canonical $Value[$Key] }
            return $Sorted
        }
        if ($Value -is [System.Collections.IList]) { return , @(foreach ($Entry in $Value) { ConvertTo-Canonical $Entry }) }
        $Value
    }
    function Get-ImportJson ([string]$Body) { ConvertTo-Canonical ($Body | ConvertFrom-Json -AsHashtable -NoEnumerate) | ConvertTo-Json -Depth 10 -Compress }
    function Get-QueuedItem ([hashtable]$Body, [hashtable]$Headers) {
        $Request = if ($Headers) { New-Request $Body $Headers } else { New-Request $Body }
        $Response = Invoke-AddDefenderIndicator -Request $Request
        $Response.StatusCode | Should -Be 202
        $Task = @($script:Started[0].Batch)[0]
        @{
            Craft  = ConvertTo-Json -InputObject $Task -Depth 10 -Compress
            Legacy = [string]($Task | ConvertTo-Json -Depth 10 -Compress)
        }
    }
}

Describe 'Push-ExecAddDefenderIndicator' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        $script:Started = [System.Collections.Generic.List[object]]::new()
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        $script:Existing = @()
        $script:NextId = 100
        $script:Tenants = @($script:TenantA)
        Mock Get-Tenants { foreach ($Tenant in $script:Tenants) { if (-not $TenantFilter -or $Tenant.customerId -eq $TenantFilter) { $Tenant } } }
        Mock Get-CIPPDefenderIndicator { $script:Existing }
        Mock New-GraphPOSTRequest {
            $script:Posts.Add([pscustomobject]@{ Tenant = $tenantid; Body = $body })
            [pscustomobject]@{ value = @(foreach ($Item in ($body | ConvertFrom-Json).Indicators) { [pscustomobject]@{ id = "$(($script:NextId++))"; indicator = $Item.indicatorValue; isFailed = $false; failureReason = $null } }) }
        }
        Mock New-CippQueueEntry { @{ PartitionKey = 'CippQueue'; RowKey = 'queue-1' } }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock Add-CIPPAzDataTableEntity { $script:Rows.Add($Entity) }
        Mock Get-CippApiClient { [pscustomobject]@{ AppName = 'PSA sync' } }
    }

    Context 'batch round trip' {
        It 'sends Defender the same request as an inline add, through the <Starter> starter, for <Case>' -ForEach @(
            foreach ($Starter in 'Craft', 'Legacy') {
                @{ Starter = $Starter; Case = 'one value'; Count = 1; Extra = @{} }
                @{ Starter = $Starter; Case = '500 values with optional fields, a UTC expiry and an ISO timestamp as title text'; Count = 500; Extra = @{ Action = 'Audit'; Title = '2026-11-23T19:15:00Z'; Description = 'Ticket 4411 at 50%'; Severity = 'High'; ExpirationTime = 'Expiry' } }
            }
        ) {
            $Body = @{ tenantFilter = 'a.com'; IndicatorType = 'FileSha256'; Action = 'Block'; Title = 'Known bad'; Values = @(foreach ($Index in 1..$Count) { '{0:x64}' -f $Index }) }
            foreach ($Key in $Extra.Keys) { $Body[$Key] = $Extra[$Key] }
            if ($Body.ExpirationTime) { $Body.ExpirationTime = [datetime]::UtcNow.AddHours(3).ToString('o') }

            $Inline = Invoke-AddDefenderIndicator -Request (New-Request $Body)
            $Inline.StatusCode | Should -Be 200
            $Expected = Get-ImportJson $script:Posts[0].Body
            $script:Posts.Clear()

            $Body.tenantFilter = 'AllTenants'
            $Json = (Get-QueuedItem $Body)[$Starter]
            Push-ExecAddDefenderIndicator -Item ($Json | ConvertFrom-Json)

            $script:Posts | Should -HaveCount 1
            $script:Posts[0].Tenant | Should -Be 'a.com'
            Get-ImportJson $script:Posts[0].Body | Should -BeExactly $Expected
            @(($script:Posts[0].Body | ConvertFrom-Json -AsHashtable).Indicators) | Should -HaveCount $Count
            if ($Body.ExpirationTime) {
                $script:Posts[0].Body | Should -Match '"expirationTime":"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"'
                $script:Posts[0].Body | Should -Match ('"title":"' + [regex]::Escape($Body.Title) + '"')
            }
        }
    }

    Context 'tenant and expiry checks' {
        It 'writes to the current domain of a renamed tenant' {
            $Json = (Get-QueuedItem @{ tenantFilter = 'AllTenants'; IndicatorType = 'DomainName'; Action = 'Block'; Title = 'Known bad'; Values = @('bad.example') }).Craft
            $script:Tenants = @([pscustomobject]@{ customerId = $script:TenantA.customerId; defaultDomainName = 'renamed.example'; initialDomainName = 'a.onmicrosoft.com' })
            Push-ExecAddDefenderIndicator -Item ($Json | ConvertFrom-Json)
            $script:Posts.Tenant | Should -Be @('renamed.example')
            $script:Rows[-1].Tenant | Should -Be 'renamed.example'
            $script:Rows[-1].TenantID | Should -Be $script:TenantA.customerId
        }

        It 'fails without calling Defender when the tenant is no longer managed' {
            $Json = (Get-QueuedItem @{ tenantFilter = 'AllTenants'; IndicatorType = 'DomainName'; Action = 'Block'; Title = 'Known bad'; Values = @('bad.example') }).Craft
            $script:Tenants = @()
            { Push-ExecAddDefenderIndicator -Item ($Json | ConvertFrom-Json) } | Should -Throw '*no longer manages it*'
            Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            $script:Rows | Should -HaveCount 1
            $script:Rows[0].Severity | Should -Be 'Error'
            $script:Rows[0].TenantID | Should -Be $script:TenantA.customerId
        }

        It 'logs a tenant lookup error without calling Defender' {
            $Json = (Get-QueuedItem @{ tenantFilter = 'AllTenants'; IndicatorType = 'DomainName'; Action = 'Block'; Title = 'Known bad'; Values = @('bad.example') }).Craft
            $ErrorActionPreference = 'Continue'
            Mock Get-Tenants { Write-Error 'Table unavailable' }

            { Push-ExecAddDefenderIndicator -Item ($Json | ConvertFrom-Json) } | Should -Throw '*Table unavailable*'
            Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            $script:Rows | Should -HaveCount 1
            $script:Rows[0].Severity | Should -Be 'Error'
            $script:Rows[0].Tenant | Should -Be 'a.com'
            $script:Rows[0].TenantID | Should -Be $script:TenantA.customerId
            $script:Rows[0].Message | Should -BeLike '*could not look up*Table unavailable*queue queue-1*'
            ($script:Rows[0].LogData | ConvertFrom-Json).QueueId | Should -Be 'queue-1'
        }

        It 'fails without calling Defender when the expiry passed while the task waited' {
            $Item = (Get-QueuedItem @{ tenantFilter = 'AllTenants'; IndicatorType = 'DomainName'; Action = 'Block'; Title = 'Known bad'; Values = @('bad.example'); ExpirationTime = [datetime]::UtcNow.AddHours(1).ToString('o') }).Craft | ConvertFrom-Json
            $ExpiredTemplate = $Item.TemplateJson | ConvertFrom-Json -AsHashtable
            $ExpiredTemplate.expirationTime = [datetime]::UtcNow.AddMinutes(-1).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            $Item.TemplateJson = ConvertTo-Json -InputObject $ExpiredTemplate -Compress
            { Push-ExecAddDefenderIndicator -Item $Item } | Should -Throw '*passed before the task ran*'
            Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            $script:Rows[0].Severity | Should -Be 'Error'
        }
    }

    Context 'outcome' {
        It 'completes and logs Info for a full success' {
            $Json = (Get-QueuedItem @{ tenantFilter = 'AllTenants'; IndicatorType = 'DomainName'; Action = 'Block'; Title = 'Known bad'; Values = @('bad.example') }).Craft
            { Push-ExecAddDefenderIndicator -Item ($Json | ConvertFrom-Json) } | Should -Not -Throw
            $script:Rows[0].Severity | Should -Be 'Info'
            $LogData = $script:Rows[0].LogData | ConvertFrom-Json
            $LogData.QueueId | Should -Be 'queue-1'
            $LogData.Results[0].resultText | Should -Be 'Added Block indicator bad.example in a.com.'
        }

        It 'fails the task after logging when some values fail, and leaves the next tenant able to complete' {
            $script:Tenants = @($script:TenantA, [pscustomobject]@{ customerId = '0b5ee4a1-0000-4000-8000-0000000000b2'; defaultDomainName = 'b.com'; initialDomainName = 'b.onmicrosoft.com' })
            $Response = Invoke-AddDefenderIndicator -Request (New-Request @{ tenantFilter = 'AllTenants'; IndicatorType = 'DomainName'; Action = 'Block'; Title = 'Known bad'; Values = @('bad.example', 'worse.example') })
            $Response.StatusCode | Should -Be 202
            $Tasks = @(foreach ($Task in @($script:Started[0].Batch)) { ConvertTo-Json -InputObject $Task -Depth 10 -Compress | ConvertFrom-Json })
            Mock Get-CIPPDefenderIndicator -ParameterFilter { $TenantFilter -eq 'a.com' } { @{ id = '7'; indicatorValue = 'bad.example'; indicatorType = 'DomainName'; action = 'Allowed' } }
            { Push-ExecAddDefenderIndicator -Item $Tasks[0] } | Should -Throw '1 of 2 Block DomainName indicators in a.com were skipped, refused or not confirmed*logbook entry for queue queue-1*before adding them again.'
            $script:Rows[0].Severity | Should -Be 'Warning'
            @(($script:Rows[0].LogData | ConvertFrom-Json).Results.state) | Should -Be @('warning', 'success')
            { Push-ExecAddDefenderIndicator -Item $Tasks[1] } | Should -Not -Throw
            $script:Posts.Tenant | Should -Be @('a.com', 'b.com')
            $script:Rows[1].Severity | Should -Be 'Info'
        }
    }

    Context 'logbook attribution' {
        It 'records the technician and their address for an interactive user' {
            $Json = (Get-QueuedItem @{ tenantFilter = 'AllTenants'; IndicatorType = 'DomainName'; Action = 'Block'; Title = 'Known bad'; Values = @('bad.example') }).Legacy
            Push-ExecAddDefenderIndicator -Item ($Json | ConvertFrom-Json)
            $script:Rows[0].Username | Should -BeExactly 'tech@msp.example'
            $script:Rows[0].IP | Should -BeExactly '198.51.100.20'
            $script:Rows[0].Keys | Should -Not -Contain 'AppId'
        }

        It 'records the API client and its app id for an API caller' {
            $Headers = @{ 'x-ms-client-principal-idp' = 'aad'; 'x-ms-client-principal-name' = '6b1f9a52-0000-4000-8000-00000000c1a0'; 'x-ms-client-principal' = (New-Principal '6b1f9a52-0000-4000-8000-00000000c1a0') }
            $Json = (Get-QueuedItem @{ tenantFilter = 'AllTenants'; IndicatorType = 'DomainName'; Action = 'Block'; Title = 'Known bad'; Values = @('bad.example') } $Headers).Legacy
            Push-ExecAddDefenderIndicator -Item ($Json | ConvertFrom-Json)
            $script:Rows[0].Username | Should -BeExactly 'PSA sync'
            $script:Rows[0].AppId | Should -BeExactly '6b1f9a52-0000-4000-8000-00000000c1a0'
            Should -Invoke Get-CippApiClient -Times 1 -Exactly -ParameterFilter { $AppId -eq '6b1f9a52-0000-4000-8000-00000000c1a0' }
        }
    }
}
