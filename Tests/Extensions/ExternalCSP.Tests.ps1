# Pester tests for the External CSP integration: the vendor contract (what CIPP sends where) and the
# quantity arithmetic that turns Add/Remove into the absolute quantity the vendor receives.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context) }
    function Get-Tenants { param($TenantFilter) }
    function Get-ExtensionAPIKey { param($Extension) }
    function Get-CippApiClient { param($AppId) }
    function Get-CIPPAccessRole { param($Headers) }
    function Get-CIPPFeatureFlag { param($Id) [pscustomobject]@{ Id = $Id; Enabled = $true } }
    function Invoke-RestMethod { param($Uri, $Method, $Headers, $Body, $ContentType) }

    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/ExternalCSP/Invoke-ExternalCSPRequest.ps1')
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/ExternalCSP/Set-ExternalCSPSubscription.ps1')

    $script:TenantId = '11111111-2222-4333-8444-555555555555'

    function Set-TestConfig {
        param([hashtable]$Override = @{})
        $Generic = @{
            Enabled          = $true
            TestUrl          = 'https://vendor.example/test'
            CatalogUrl       = 'https://vendor.example/catalog'
            SubscriptionsUrl = 'https://vendor.example/subscriptions?v=1'
            OrderUrl         = 'https://vendor.example/orders'
            QuantityUrl      = 'https://vendor.example/quantity'
            CancelUrl        = 'https://vendor.example/cancel'
        }
        foreach ($Key in $Override.Keys) { $Generic[$Key] = $Override[$Key] }
        $script:ConfigJson = @{ ExternalCSP = $Generic } | ConvertTo-Json -Depth 10
    }
}

Describe 'Invoke-ExternalCSPRequest' {
    BeforeEach {
        Set-TestConfig
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ config = $script:ConfigJson } }
        Mock Get-Tenants { [pscustomobject]@{ customerId = $script:TenantId } }
        Mock Get-ExtensionAPIKey { 'secret-key' }
        Mock Invoke-RestMethod { @([pscustomobject]@{ sku = 'A' }, [pscustomobject]@{ sku = 'B' }) }
    }

    It 'reads with a GET, the API key header, and tenantId in the query' {
        $Result = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'

        $Result.Count | Should -Be 2
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq "https://vendor.example/catalog?tenantId=$script:TenantId" -and $Headers.'x-api-key' -eq 'secret-key'
        }
    }

    It 'appends tenantId to a URL that already has a query string' {
        $null = Invoke-ExternalCSPRequest -Action Subscriptions -TenantFilter 'contoso.com'

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq "https://vendor.example/subscriptions?v=1&tenantId=$script:TenantId"
        }
    }

    It 'writes with a JSON POST that identifies the customer by tenantId only' {
        $null = Invoke-ExternalCSPRequest -Action Order -TenantFilter 'contoso.com' -Body @{ sku = 'A'; quantity = 2 }

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Sent = $Body | ConvertFrom-Json
            $Method -eq 'POST' -and $Uri -eq 'https://vendor.example/orders' -and $ContentType -eq 'application/json' -and
            $Sent.tenantId -eq $script:TenantId -and $Sent.sku -eq 'A' -and $Sent.quantity -eq 2 -and
            $Sent.PSObject.Properties.Name -notcontains 'defaultDomain'
        }
    }

    It 'refuses a URL that is not https and sends nothing' {
        Set-TestConfig -Override @{ CatalogUrl = 'http://169.254.169.254/latest' }

        { Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com' } | Should -Throw '*https://*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'surfaces the vendor message from a rejected request' {
        Mock Invoke-RestMethod {
            $Record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Response status code does not indicate success: 409'), 'Http', 'NotSpecified', $null)
            $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"message":"Seat limit reached for this customer"}')
            throw $Record
        }

        { Invoke-ExternalCSPRequest -Action Order -TenantFilter 'contoso.com' -Body @{ sku = 'A'; quantity = 1 } } |
            Should -Throw '*Seat limit reached for this customer*'
    }

    It 'treats a 2xx success:false body as a refusal on a <Action> call' -ForEach @(
        @{ Action = 'Order'; Body = @{ sku = 'A'; quantity = 1 } }
        @{ Action = 'Catalog'; Body = @{} }
    ) {
        Mock Invoke-RestMethod { [pscustomobject]@{ success = $false; message = 'Orders over 100 licences need distributor approval.' } }

        { Invoke-ExternalCSPRequest -Action $Action -TenantFilter 'contoso.com' -Body $Body } |
            Should -Throw "*rejected the $Action request: Orders over 100 licences need distributor approval.*"
    }

    It 'still refuses a 2xx success:false body that gives no message' {
        Mock Invoke-RestMethod { [pscustomobject]@{ success = $false } }

        { Invoke-ExternalCSPRequest -Action Order -TenantFilter 'contoso.com' -Body @{ sku = 'A'; quantity = 1 } } |
            Should -Throw '*no reason was given*'
    }

    It 'accepts a 2xx body whose success flag is true or absent' {
        Mock Invoke-RestMethod { [pscustomobject]@{ success = $true; status = 'accepted' } }
        (Invoke-ExternalCSPRequest -Action Order -TenantFilter 'contoso.com' -Body @{ sku = 'A'; quantity = 1 }).status | Should -Be 'accepted'

        Mock Invoke-RestMethod { [pscustomobject]@{ status = 'accepted' } }
        (Invoke-ExternalCSPRequest -Action Order -TenantFilter 'contoso.com' -Body @{ sku = 'A'; quantity = 1 }).status | Should -Be 'accepted'
    }

    It 'says the provider gave no reason when a 5xx carries no message' {
        Mock Invoke-RestMethod {
            $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadGateway)
            $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success: 502 (Bad Gateway).', $Response)
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'Http', 'NotSpecified', $null)
            $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('error code: 502')
            throw $Record
        }

        { Invoke-ExternalCSPRequest -Action Quantity -TenantFilter 'contoso.com' -Body @{ subscriptionId = 's'; quantity = 1 } } |
            Should -Throw '*could not process the Quantity request (HTTP 502) and gave no reason*'
    }

    It 'makes no call to the provider while the feature flag is off' {
        Mock Get-CIPPFeatureFlag { [pscustomobject]@{ Id = 'ExternalCSP'; Enabled = $false } }

        { Invoke-ExternalCSPRequest -Action Order -TenantFilter 'contoso.com' -Body @{ sku = 'A'; quantity = 1 } } | Should -Throw '*turned off*'
        { Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com' } | Should -Throw '*turned off*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'calls the test URL with credentials and no tenant' {
        $null = Invoke-ExternalCSPRequest -Action Test

        Should -Invoke Get-Tenants -Times 0
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'https://vendor.example/test' -and $Headers.'x-api-key' -eq 'secret-key'
        }
    }

    Context 'authentication' {
        It 'sends the secret in a custom-named API key header' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'ApiKey' }; AuthHeaderName = 'X-Vendor-Key' }
            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers.'X-Vendor-Key' -eq 'secret-key' -and $Headers.Count -eq 1 }
        }

        It 'sends the secret as a bearer token' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'Bearer' } }
            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers.Authorization -eq 'Bearer secret-key' }
        }

        It 'sends the username and secret as basic auth' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'Basic' }; AuthUsername = 'cipp' }
            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'
            # base64 of "cipp:secret-key"
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers.Authorization -eq 'Basic Y2lwcDpzZWNyZXQta2V5' }
        }

        It 'sends every header from a custom headers JSON secret' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'CustomHeaders' } }
            Mock Get-ExtensionAPIKey { '{"x-partner-id":"p-1","x-partner-secret":"s-1"}' }
            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers.'x-partner-id' -eq 'p-1' -and $Headers.'x-partner-secret' -eq 's-1' }
        }

        It 'refuses to call the vendor when the custom headers secret is not a JSON object' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'CustomHeaders' } }
            Mock Get-ExtensionAPIKey { 'not json' }
            { Invoke-ExternalCSPRequest -Action Order -TenantFilter 'contoso.com' -Body @{ sku = 'A'; quantity = 1 } } | Should -Throw '*must be a JSON object*'
            Should -Invoke Invoke-RestMethod -Times 0
        }
    }

    Context 'forgiving credential entry' {
        It 'does not repeat the Bearer scheme when the token was pasted with it' -ForEach @(
            @{ Pasted = 'Bearer secret-key' }
            @{ Pasted = 'bearer   secret-key' }
            @{ Pasted = 'Authorization: Bearer secret-key' }
            @{ Pasted = "  secret-key`n" }
        ) {
            Set-TestConfig -Override @{ AuthType = @{ value = 'Bearer' } }
            Mock Get-ExtensionAPIKey { $Pasted }
            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers.Authorization -ceq 'Bearer secret-key' }
        }

        It 'sends an already encoded Basic credential as it is' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'Basic' }; AuthUsername = 'cipp' }
            Mock Get-ExtensionAPIKey { 'Basic Y2lwcDpzZWNyZXQta2V5' }
            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers.Authorization -eq 'Basic Y2lwcDpzZWNyZXQta2V5' }
        }

        It 'accepts username:password in the secret when no username was entered' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'Basic' } }
            Mock Get-ExtensionAPIKey { 'cipp:secret-key' }
            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers.Authorization -eq 'Basic Y2lwcDpzZWNyZXQta2V5' }
        }

        It 'refuses basic auth with no username at all' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'Basic' } }
            { Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com' } | Should -Throw '*needs a username*'
            Should -Invoke Invoke-RestMethod -Times 0
        }

        It 'cleans a header name typed with a colon and a key pasted with its header name' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'ApiKey' }; AuthHeaderName = ' X-Vendor-Key: ' }
            Mock Get-ExtensionAPIKey { 'x-vendor-key: secret-key' }
            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers.'X-Vendor-Key' -eq 'secret-key' -and $Headers.Count -eq 1 }
        }

        It 'trims custom header names and values and skips blank ones' {
            Set-TestConfig -Override @{ AuthType = @{ value = 'CustomHeaders' } }
            Mock Get-ExtensionAPIKey { '{" x-partner-id: ":" p-1 ","":"ignored","x-empty":null}' }
            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers.'x-partner-id' -eq 'p-1' -and $Headers.Count -eq 1 }
        }

        It 'refuses to call the vendor when no secret is stored' {
            Mock Get-ExtensionAPIKey { $null }
            { Invoke-ExternalCSPRequest -Action Order -TenantFilter 'contoso.com' -Body @{ sku = 'A'; quantity = 1 } } | Should -Throw '*secret is not set*'
            Should -Invoke Invoke-RestMethod -Times 0
        }
    }

    Context 'purchase role gate' {
        BeforeEach {
            Set-TestConfig -Override @{ AllowedCustomRoles = @{ value = @('licence-buyers') } }
            $script:UserHeaders = @{ 'x-ms-client-principal' = 'encoded-principal' }
        }

        It 'blocks a write from a caller without an allowed role' {
            Mock Get-CIPPAccessRole { @('readonly') }

            { Invoke-ExternalCSPRequest -Action Order -TenantFilter 'contoso.com' -Headers $script:UserHeaders -Body @{ sku = 'A'; quantity = 1 } } |
                Should -Throw '*not allowed to modify CSP subscriptions*'
            Should -Invoke Invoke-RestMethod -Times 0
        }

        It 'allows a write from a caller holding an allowed role' {
            Mock Get-CIPPAccessRole { @('readonly', 'licence-buyers') }

            $null = Invoke-ExternalCSPRequest -Action Cancel -TenantFilter 'contoso.com' -Headers $script:UserHeaders -Body @{ subscriptionIds = @('sub-1') }
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        It 'does not gate reads' {
            Mock Get-CIPPAccessRole { @('readonly') }

            $null = Invoke-ExternalCSPRequest -Action Catalog -TenantFilter 'contoso.com' -Headers $script:UserHeaders
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
    }
}

Describe 'Set-ExternalCSPSubscription' {
    BeforeEach {
        $script:Posted = $null
        Mock Invoke-ExternalCSPRequest -ParameterFilter { $Action -eq 'Subscriptions' } -MockWith {
            @(
                [pscustomobject]@{ subscriptionId = 'sub-other'; sku = 'OTHER'; quantity = 3 }
                [pscustomobject]@{ subscriptionId = 'sub-1'; sku = 'BP'; quantity = 15 }
            )
        }
        Mock Invoke-ExternalCSPRequest -ParameterFilter { $Action -ne 'Subscriptions' } -MockWith {
            $script:Posted = @{ Action = $Action; Body = $Body }
        }
    }

    It 'sends the new absolute quantity when adding' {
        Set-ExternalCSPSubscription -TenantFilter 'contoso.com' -SKU 'BP' -Add 2

        $script:Posted.Action | Should -Be 'Quantity'
        $script:Posted.Body.subscriptionId | Should -Be 'sub-1'
        $script:Posted.Body.quantity | Should -Be 17
    }

    It 'sends the new absolute quantity when removing' {
        Set-ExternalCSPSubscription -TenantFilter 'contoso.com' -SKU 'BP' -Remove 5

        $script:Posted.Body.quantity | Should -Be 10
    }

    It 'refuses to drop an existing subscription below one licence' {
        { Set-ExternalCSPSubscription -TenantFilter 'contoso.com' -SKU 'BP' -Remove 15 } | Should -Throw '*at least 1*'
        $script:Posted | Should -BeNullOrEmpty
    }

    It 'places a new order when the tenant has no subscription for the SKU' {
        Set-ExternalCSPSubscription -TenantFilter 'contoso.com' -SKU 'NEW' -Quantity 4

        $script:Posted.Action | Should -Be 'Order'
        $script:Posted.Body.sku | Should -Be 'NEW'
        $script:Posted.Body.quantity | Should -Be 4
    }

    It 'refuses Add when there is no subscription to add to' {
        { Set-ExternalCSPSubscription -TenantFilter 'contoso.com' -SKU 'NEW' -Add 1 } | Should -Throw '*No existing subscription*'
        $script:Posted | Should -BeNullOrEmpty
    }
}
