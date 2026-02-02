function Set-CIPPDbCacheTestData {
    <#
    .SYNOPSIS
        Generates test data for cache performance testing

    .DESCRIPTION
        Creates 50,000 test objects with ~3KB of data each to test streaming performance

    .PARAMETER TenantFilter
        The tenant to use for test data

    .PARAMETER Count
        Number of test objects to generate (default: 50000)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

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

        $startTime = Get-Date

        Write-Information "[Set-CIPPDbCacheTestData] Starting generation of $Count test objects for tenant $TenantFilter"
        # Stream test objects directly to batch processor
        1..$Count | ForEach-Object {
            [PSCustomObject]@{
                id                 = [guid]::NewGuid().ToString()
                displayName        = "Test User $_"
                userPrincipalName  = "testuser$_@$TenantFilter"
                mail               = "testuser$_@$TenantFilter"
                givenName          = 'Test'
                surname            = "User $_"
                jobTitle           = 'Test Engineer'
                department         = 'Testing Department'
                officeLocation     = "Test Office $_"
                mobilePhone        = "+1-555-000-$($_.ToString().PadLeft(4, '0'))"
                businessPhones     = @("+1-555-001-$($_.ToString().PadLeft(4, '0'))")
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
                proxyAddresses     = @("SMTP:testuser$_@$TenantFilter", "smtp:alias$_@$TenantFilter")
                assignedLicenses   = @(
                    @{ skuId = [guid]::NewGuid().ToString(); disabledPlans = @() }
                )
                customAttribute1   = 'Custom Value 1'
                customAttribute2   = 'Custom Value 2'
                customAttribute3   = 'Custom Value 3'
                additionalData     = $sampleText
            }
        } | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'TestData' -AddCount

        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        $objectsPerSecond = [math]::Round($Count / $duration, 2)

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Generated $Count test objects in $duration seconds ($objectsPerSecond objects/sec)" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to generate test data: $($_.Exception.Message)" -sev Error
    }
}
