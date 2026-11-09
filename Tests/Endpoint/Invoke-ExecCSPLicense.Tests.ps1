# Pester tests for Invoke-ExecCSPLicense's ScheduleRemoval action.
#
# The scheduled decrease used to run three days BEFORE the renewal date. Microsoft NCE subscriptions
# with a commitment term can only be decreased in the first seven days of a new term, so every such
# task failed with Sherweb's 412 commitment-term-violations error (GitHub issue 1169). The task now runs
# shortly AFTER the renewal date, clamped so it always lands inside that seven-day window.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecCSPLicense.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecCSPLicense.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Set-SherwebSubscription { param($Headers, $tenantFilter, $SKU, $Add, $Remove, $Quantity) }
    function Remove-SherwebSubscription { param($Headers, $tenantFilter, $SubscriptionIds) }
    function Get-SherwebCurrentSubscription { param($TenantFilter, $CustomerId, $SKU, $ProductName) }
    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers) }

    . $FunctionPath

    function New-ScheduleRequest {
        param([hashtable]$Body = @{})
        $Defaults = @{
            tenantFilter = 'contoso.onmicrosoft.com'
            Action       = 'ScheduleRemoval'
            SKU          = 'SW-P-O365-15-M1M'
            Remove       = 1
        }
        foreach ($Key in $Body.Keys) { $Defaults[$Key] = $Body[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecCSPLicense' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]$Defaults
        }
    }

    function New-Subscription {
        param([string]$RenewalDate)
        [pscustomobject]@{
            id             = 'aaaaaaaa-0000-4000-8000-000000000001'
            sku            = 'SW-P-O365-15-M1M'
            productName    = 'Microsoft 365 Business Premium'
            quantity       = 15
            commitmentTerm = [pscustomobject]@{
                type                 = 'Monthly'
                renewalConfiguration = if ($RenewalDate) { [pscustomobject]@{ renewalDate = $RenewalDate } } else { $null }
            }
        }
    }
}

Describe 'Invoke-ExecCSPLicense ScheduleRemoval' {
    BeforeEach {
        $script:Scheduled = $null
        Mock Add-CIPPScheduledTask { $script:Scheduled = $Task }
        $script:RenewalDate = [datetime]::UtcNow.Date.AddDays(30).ToString('yyyy-MM-dd')
        Mock Get-SherwebCurrentSubscription { New-Subscription -RenewalDate $script:RenewalDate }
    }

    It 'schedules the task one day AFTER the renewal date by default' {
        $Response = Invoke-ExecCSPLicense -Request (New-ScheduleRequest) -TriggerMetadata @{}

        $Response.StatusCode | Should -Be 200
        $Expected = [datetimeoffset]::new([datetime]::SpecifyKind(([datetime]$script:RenewalDate).AddDays(1), 'Utc')).ToUnixTimeSeconds()
        $script:Scheduled.ScheduledTime | Should -Be $Expected
        $script:Scheduled.Command.value | Should -Be 'Invoke-SherwebScheduledLicenseRemoval'
        $script:Scheduled.Parameters.SKU | Should -Be 'SW-P-O365-15-M1M'
        $script:Scheduled.Parameters.Remove | Should -Be 1
        $Response.Body | Should -BeLike '*1 day(s) after the renewal date*'
    }

    It 'honours a requested number of days after renewal' {
        $null = Invoke-ExecCSPLicense -Request (New-ScheduleRequest -Body @{ DaysAfterRenewal = 3 }) -TriggerMetadata @{}

        $Expected = [datetimeoffset]::new([datetime]::SpecifyKind(([datetime]$script:RenewalDate).AddDays(3), 'Utc')).ToUnixTimeSeconds()
        $script:Scheduled.ScheduledTime | Should -Be $Expected
    }

    It 'never schedules outside the seven-day decrease window' {
        $null = Invoke-ExecCSPLicense -Request (New-ScheduleRequest -Body @{ DaysAfterRenewal = 20 }) -TriggerMetadata @{}

        $Expected = [datetimeoffset]::new([datetime]::SpecifyKind(([datetime]$script:RenewalDate).AddDays(6), 'Utc')).ToUnixTimeSeconds()
        $script:Scheduled.ScheduledTime | Should -Be $Expected
    }

    It 'never schedules before the renewal date, whatever the caller sends' {
        $null = Invoke-ExecCSPLicense -Request (New-ScheduleRequest -Body @{ DaysAfterRenewal = -3 }) -TriggerMetadata @{}

        $RenewalUnix = [datetimeoffset]::new([datetime]::SpecifyKind(([datetime]$script:RenewalDate), 'Utc')).ToUnixTimeSeconds()
        $script:Scheduled.ScheduledTime | Should -BeGreaterThan $RenewalUnix
    }

    It 'refuses when the run date is already in the past' {
        $script:RenewalDate = [datetime]::UtcNow.Date.AddDays(-10).ToString('yyyy-MM-dd')

        $Response = Invoke-ExecCSPLicense -Request (New-ScheduleRequest) -TriggerMetadata @{}

        $Response.StatusCode | Should -Be 500
        $Response.Body | Should -BeLike '*already in the past*'
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'refuses when the subscription has no renewal date' {
        Mock Get-SherwebCurrentSubscription { New-Subscription -RenewalDate $null }

        $Response = Invoke-ExecCSPLicense -Request (New-ScheduleRequest) -TriggerMetadata @{}

        $Response.StatusCode | Should -Be 500
        $Response.Body | Should -BeLike '*does not have a renewal date*'
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }
}
