using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
Function Test-CronRange {
    <#
        .EXAMPLE
            # * always passes
            Test-CronRange -Range '*' -InputValue 10 -Verbose
            # a min-max range
            Test-CronRange -Range '1-15' -InputValue 10 -Verbose
            # stepped value
            Test-CronRange -Range '*/15' -InputValue 30 -verbose
            # A specific value list
            Test-CronRange -Range '2,5,8,9' -InputValue 10 -verbose
            Test-CronRange -Range '*/4' -InputValue 60 -verbose
    #>
    [cmdletbinding()]
    param(
        [ValidatePattern('^[\d-*/,]*$')]
        [string]$range
        ,
        [int]$inputvalue
    )
    Write-Verbose "Testing $range"
    If ($range -eq '*') {
        Return $true
    }
    If ($range -match '^\d+$') {
        Write-Verbose 'Specific Value(int)'
        Return ($inputvalue -eq [int]$range)
    }
    If ($range -match '[\d]+-[\d]+([/][\d])*') {
        Write-Verbose 'min-max range'
        [int]$min, [int]$max = $range -split '-'
        Return ($inputvalue -ge $min -and $inputvalue -le $max)
    }
    If ($range -match ('([*]+|[\d]+-[\d]+)[/][\d]+')) {
        Write-Verbose 'Step Value'
        $list, $step = $range -split '/'
        Write-Verbose "Using Step of $step"
        $IsInStep = ( ($inputvalue / $step).GetType().Name -eq 'Int32' )
        Return ( $IsInStep )
    }
    If ($range -match '(\d+)(,\s*\d+)*') {
        Write-Verbose 'value list'
        $list = @()
        $list = $range -split ','
        Return ( $list -contains $InputValue )
    }    
    Write-Error "Could not process Range format: $Range"
}
Function ConvertFrom-DateTable {
    Param (
        $DateTable
    )
    $datestring = '{0}-{1:00}-{2:00} {3:00}:{4:00}' -f $DateTable.year, $DateTable.month, $DateTable.day, $DateTable.hour, $DateTable.Minute
    $date = [datetime]::ParseExact($datestring, 'yyyy-MM-dd HH:mm', $null)
    return $date
}
Function Invoke-CronIncrement {
    param(
        [psobject]
        $DateTable
        ,
        [ValidateSet('Minute', 'Hour', 'Day', 'Month')]
        [string]
        $Increment
    )
    $date = ConvertFrom-DateTable -DateTable $DateTable
    $date = switch ($Increment) {
        'Minute' { $date.AddMinutes(1) } 
        'Hour' { $date.AddHours(1) }
        'Day' { $date.AddDays(1) }
        'Month' { $date.AddMonths(1) }
    }
    $output = [ordered]@{
        Minute  = $date.Minute
        Hour    = $date.hour
        Day     = $date.day
        Weekday = $date.DayOfWeek.value__
        Month   = $date.month
        Year    = $date.year
    }
    Return $output
}
Function Get-CronNextExecutionTime {
    <#
        .SYNOPSIS
            Currently only support * or digits
            todo: add support for ',' '-' '/' ','
        .EXAMPLE
            Get-CronNextExecutionTime -Expression '* * * * *'
            Get-CronNextExecutionTime -Expression '5 * * * *'
            Get-CronNextExecutionTime -Expression '* 13-21 * * *'
            Get-CronNextExecutionTime -Expression '0 0 2 * *'
            Get-CronNextExecutionTime -Expression '15 14 * 1-3 *'
            Get-CronNextExecutionTime -Expression '15 14 * * 4'
            Get-CronNextExecutionTime -Expression '15 14 * 2 *'
            Get-CronNextExecutionTime -Expression '15 14-20 * * *'
            Get-CronNextExecutionTime -Expression '15 14 * * 1'
    #>
    [cmdletbinding()]
    param(
        [string]
        $Expression = '* * * * *'
        ,
        $InputDate
    )
    # Split Expression in variables and set to INT if possible
    $cronMinute, $cronHour, $cronDay, $cronMonth, $cronWeekday = $Expression -Split ' '
    Get-Variable -Scope local | Where-Object { $_.name -like 'cron*' } | ForEach-Object {
        If ($_.Value -ne '*') {
            Try {
                [int]$newValue = $_.Value
                Set-Variable -Name $_.Name -Value $newValue -ErrorAction Ignore
            }
            Catch {}
        }
    }
    # Get the next default Time (= next minute)
    $nextdate = If ($InputDate) { $InputDate } Else { Get-Date }
    $nextdate = $nextdate.addMinutes(1)
    $next = [ordered]@{
        Minute  = $nextdate.Minute
        Hour    = $nextdate.hour
        Day     = $nextdate.day
        Weekday = $nextdate.DayOfWeek.value__
        Month   = $nextdate.month
        Year    = $nextdate.year
    }
    # Increase Minutes until it is in the range.
    # If Minutes passes the 60 mark, the hour is incremented
    $done = $false
    Do {
        If ((Test-CronRange -InputValue $next.Minute -range $cronMinute) -eq $False) {
            Do {
                $next = Invoke-CronIncrement -DateTable $Next -Increment Minute
            } While ( (Test-CronRange -InputValue $next.Minute -range $cronMinute) -eq $False )
            continue
        }
        # Check if the next Hour is in the desired range
        # Add a Day because the desired Hour has already passed
        If ((Test-CronRange -InputValue $next.Hour -range $cronHour) -eq $False) {
            Do {
                $next = Invoke-CronIncrement -DateTable $Next -Increment Hour
                $next.Minute = 0                
            } While ((Test-CronRange -InputValue $next.Hour -range $cronHour) -eq $False)
            continue
        }
        # Increase Days until it is in the range.
        # If Days passes the 30/31 mark, the Month is incremented
        If ((Test-CronRange -InputValue $next.day -range $cronday) -eq $False) {
            Do {
                $next = Invoke-CronIncrement -DateTable $Next -Increment Day
                $next.Hour = 0
                $next.Minute = 0                
            } While ((Test-CronRange -InputValue $next.day -range $cronday) -eq $False)
            continue
        }
        # Increase Months until it is in the range.
        # If Months passes the 12 mark, the Year is incremented    
        If ((Test-CronRange -InputValue $next.Month -range $cronMonth) -eq $False) {
            Do {
                $next = Invoke-CronIncrement -DateTable $Next -Increment Month
                $next.Hour = 0
                $next.Minute = 0
            } While ((Test-CronRange -InputValue $next.Month -range $cronMonth) -eq $False)
            continue
        }
        If ((Test-CronRange -InputValue $Next.WeekDay -Range $cronWeekday) -eq $false) {
            Do {
                $next = Invoke-CronIncrement -DateTable $Next -Increment Day
                $next.Hour = 0
                $next.Minute = 0    
            } While ( (Test-CronRange -InputValue $Next.WeekDay -Range $cronWeekday) -eq $false )
            continue
        }
        $done = $true
    } While ($done -eq $false)
    $date = ConvertFrom-DateTable -DateTable $next
    If (!$date) { Throw 'Could not create date' }
    
    # Add Days until weekday matches
 
    Return $Date
}

$Table = Get-CippTable -tablename CippLogs
$PartitionKey = Get-Date -UFormat '%Y%m%d'
$Filter = "PartitionKey eq '{0}'" -f $PartitionKey
$Rows = Get-AzDataTableEntity @Table -Filter $Filter | Sort-Object TableTimestamp -Descending | Select-Object -First 10

$Standards = Get-CippTable -tablename standards
$QueuedStandards = (Get-AzDataTableEntity @Standards -Property RowKey | Measure-Object).Count

$Apps = Get-CippTable -tablename apps
$QueuedApps = (Get-AzDataTableEntity @Apps -Property RowKey | Measure-Object).Count

$SlimRows = New-Object System.Collections.ArrayList
foreach ($Row in $Rows) {
    $SlimRows.Add(@{
            Tenant  = $Row.Tenant
            Message = $Row.Message
        })
}
$Alerts = [System.Collections.ArrayList]@()
if ($env:ApplicationID -eq 'LongApplicationID' -or $null -eq $ENV:ApplicationID) { $Alerts.add('You have not yet setup your SAM Setup. Please go to the SAM Wizard in settings to finish setup') }
if ($env:FUNCTIONS_EXTENSION_VERSION -ne '~4') { $Alerts.add('Your Function App is running on a Runtime version lower than 4. This impacts performance. Go to Settings -> Backend -> Function App Configuration -> Function Runtime Settings and set this to 4 for maximum performance') }
if ($psversiontable.psversion.toString() -lt 7.2) { $Alerts.add('Your Function App is running on Powershell 7. This impacts performance. Go to Settings -> Backend -> Function App Configuration -> General Settings and set PowerShell Core Version to 7.2 for maximum performance') }
if ($env:WEBSITE_RUN_FROM_PACKAGE -ne '1') { $Alerts.add('Your Function App is running in write mode. Please check the release notes to enable Run from Package mode. (https://github.com/KelvinTegelaar/CIPP/releases/tag/v2.1.11.0)') }
try {
    $TenantCount = (Get-Tenants -IncludeErrors | Measure-Object).Count
    $TenantErrorCount = $TenantCount - (Get-Tenants | Measure-Object).Count
}
catch {
    $TenantCount = 0
    $TenantErrorCount = 0
}
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

if (!$env:WEBSITE_NAME) {
    #Running locally, no alerts. :)
    $Alerts = $null
}
else {
    $Alerts = @($Alerts)
}
$dash = [PSCustomObject]@{
    NextStandardsRun  = (Get-CronNextExecutionTime -Expression '0 */3 * * *').tostring('s')
    NextBPARun        = (Get-CronNextExecutionTime -Expression '0 3 * * *').tostring('s')
    queuedApps        = [int64]$QueuedApps
    queuedStandards   = [int64]$QueuedStandards
    tenantCount       = [int64]$TenantCount
    tenantErrorCount  = [int64]$TenantErrorCount
    RefreshTokenDate  = (Get-CronNextExecutionTime -Expression '0 0 * * 0').AddDays('-7').tostring('s') -split 'T' | Select-Object -First 1
    ExchangeTokenDate = (Get-CronNextExecutionTime -Expression '0 0 * * 0').AddDays('-7').tostring('s') -split 'T' | Select-Object -First 1
    LastLog           = @($SlimRows)
    Alerts            = $Alerts
}
# Write to the Azure Functions log stream.
 
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $dash
    })
