function Set-CIPPDbCacheTestData {
    <#
    .SYNOPSIS
        Generates test data for cache performance testing

    .DESCRIPTION
        Creates 50,000 test objects with ~3KB of data each to test streaming performance

    .PARAMETER TenantFilter
        The tenant to use for test data

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)

    .PARAMETER Count
        Number of test objects to generate (default: 50000)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId,

        [Parameter(Mandatory = $false)]
        [int]$Count = 50000
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Generating $Count test objects" -sev Debug

        # Generate sample data to reach ~3KB per object
        $sampleText = @'
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
'@ * 10  # Repeat to get ~3KB

        # Stopwatch is much cheaper than two Get-Date calls (Get-Date is documented in
        # the PowerShell 7.4 performance guidance as a hot path to avoid).
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        Write-Information "[Set-CIPPDbCacheTestData] Starting generation of $Count test objects for tenant $TenantFilter"

        # Stream test objects through the pipeline using `foreach` inside an inline
        # scriptblock — preserves the original streaming behaviour (so Add-CIPPDbItem
        # can flush in 500-row batches without holding all 50k rows in memory) while
        # avoiding the per-iteration ForEach-Object scriptblock dispatch and
        # PSCustomObject NoteProperty bag construction. Ordered hashtables serialize
        # identically through ConvertTo-Json downstream.
        & {
            foreach ($i in 1..$Count) {
                $padded = $i.ToString().PadLeft(4, '0')
                [ordered]@{
                    id                 = [guid]::NewGuid().ToString()
                    displayName        = "Test User $i"
                    userPrincipalName  = "testuser$i@$TenantFilter"
                    mail               = "testuser$i@$TenantFilter"
                    givenName          = 'Test'
                    surname            = "User $i"
                    jobTitle           = 'Test Engineer'
                    department         = 'Testing Department'
                    officeLocation     = "Test Office $i"
                    mobilePhone        = "+1-555-000-$padded"
                    businessPhones     = @("+1-555-001-$padded")
                    accountEnabled     = $true
                    createdDateTime    = (Get-Date).ToString('o')
                    lastSignInDateTime = (Get-Date).AddDays(-1).ToString('o')
                    description        = $sampleText
                    companyName        = 'Test Company'
                    country            = 'United States'
                    city               = 'Test City'
                    state              = 'Test State'
                    postalCode         = '12345'
                    streetAddress      = '123 Test Street'
                    proxyAddresses     = @("SMTP:testuser$i@$TenantFilter", "smtp:alias$i@$TenantFilter")
                    assignedLicenses   = @(
                        @{ skuId = [guid]::NewGuid().ToString(); disabledPlans = @() }
                    )
                    customAttribute1   = 'Custom Value 1'
                    customAttribute2   = 'Custom Value 2'
                    customAttribute3   = 'Custom Value 3'
                    additionalData     = $sampleText
                }
            }
        } | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'TestData' -AddCount

        $stopwatch.Stop()
        $duration = $stopwatch.Elapsed.TotalSeconds
        $objectsPerSecond = '{0:N2}' -f ($Count / $duration)
        $durationFmt = '{0:N3}' -f $duration

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Generated $Count test objects in $durationFmt seconds ($objectsPerSecond objects/sec)" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to generate test data: $($_.Exception.Message)" -sev Error
    }
}
